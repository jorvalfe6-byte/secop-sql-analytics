-- =====================================================================
-- 07_powerbi_extract.sql — Extracto agregado que lee el informe de Power BI.
--
-- El esquema powerbi (06) tiene un contrato por fila y medio millón de
-- proveedores: sirve para conectarse en vivo a PostgreSQL, pero como CSV
-- dentro de un repo pesaría más de 100 MB. Este esquema agrega los hechos al
-- grano más fino que pide el informe; cada medida es una suma de estas
-- columnas, así que los totales son exactos en cualquier nivel.
-- Las medianas no se pueden reconstruir con sumas: las del README salen de
-- sql/analysis. scripts/export_powerbi.sh guarda cada vista en powerbi/data/.
--
--   fact_mensual         grano: mes de firma x entidad x modalidad x tipo de persona
--   fact_duracion        grano: tramo de duración x grupo de modalidad
--   pareto_proveedores   1 fila por percentil de proveedores (ordenados por valor)
--   top_proveedores      las 100 personas jurídicas con más valor contratado
--   dim_*                dimensiones del esquema powerbi, calendario recortado a 2024
--
-- Dinero: solo contratos válidos (es_valido), como en el resto del proyecto.
-- El valor pagado se topa en el valor del contrato.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP SCHEMA IF EXISTS powerbi_extract CASCADE;
CREATE SCHEMA powerbi_extract;

CREATE VIEW powerbi_extract.fact_mensual AS
SELECT d.mes_inicio                                                       AS mes,
       f.entidad_key,
       f.modalidad_key,
       p.tipo_persona,
       COUNT(*)                                                           AS contratos,
       COUNT(*) FILTER (WHERE f.es_valido)                                AS contratos_validos,
       COALESCE(SUM(f.valor_contrato) FILTER (WHERE f.es_valido), 0)      AS valor,
       COALESCE(SUM(LEAST(COALESCE(f.valor_pagado, 0), f.valor_contrato))
                FILTER (WHERE f.es_valido), 0)                            AS valor_pagado,
       COUNT(*) FILTER (WHERE f.es_valido AND COALESCE(f.valor_pagado, 0) = 0) AS contratos_sin_pago,
       COUNT(*) FILTER (WHERE f.es_valido AND f.dias_adicionados > 0)     AS contratos_con_adicion,
       COALESCE(SUM(f.dias_adicionados) FILTER (WHERE f.es_valido AND f.dias_adicionados > 0), 0) AS dias_adicionados,
       COUNT(*) FILTER (WHERE f.es_valido AND f.duracion_dias IS NOT NULL) AS contratos_con_duracion,
       COALESCE(SUM(f.duracion_dias) FILTER (WHERE f.es_valido), 0)       AS duracion_dias_suma
FROM powerbi.fact_contrato AS f
JOIN powerbi.dim_fecha     AS d ON d.fecha_key = f.fecha_firma_key
JOIN powerbi.dim_proveedor AS p ON p.proveedor_key = f.proveedor_key
GROUP BY 1, 2, 3, 4;

CREATE VIEW powerbi_extract.fact_duracion AS
SELECT CASE
           WHEN f.duracion_dias <= 30  THEN '1. Hasta 1 mes'
           WHEN f.duracion_dias <= 90  THEN '2. 1 a 3 meses'
           WHEN f.duracion_dias <= 180 THEN '3. 3 a 6 meses'
           WHEN f.duracion_dias <= 365 THEN '4. 6 a 12 meses'
           ELSE                             '5. Más de 1 año'
       END                                  AS tramo_duracion,
       f.modalidad_key,
       COUNT(*)                             AS contratos,
       SUM(f.valor_contrato)                AS valor
FROM powerbi.fact_contrato AS f
WHERE f.es_valido AND f.duracion_dias IS NOT NULL
GROUP BY 1, 2;

-- Curva de concentración: proveedores ordenados de mayor a menor valor,
-- partidos en 100 grupos de igual tamaño.
CREATE VIEW powerbi_extract.pareto_proveedores AS
WITH por_proveedor AS (
    SELECT proveedor_key, SUM(valor_contrato) AS valor
    FROM powerbi.fact_contrato
    WHERE es_valido
    GROUP BY 1
),
percentiles AS (
    SELECT NTILE(100) OVER (ORDER BY valor DESC, proveedor_key) AS percentil, valor
    FROM por_proveedor
)
SELECT percentil,
       COUNT(*)                                                          AS proveedores,
       SUM(valor)                                                        AS valor,
       ROUND(SUM(SUM(valor)) OVER (ORDER BY percentil) / SUM(SUM(valor)) OVER (), 4) AS valor_acumulado_pct
FROM percentiles
GROUP BY percentil;

CREATE VIEW powerbi_extract.top_proveedores AS
SELECT p.proveedor, p.nit_proveedor,
       COUNT(*)                          AS contratos,
       COUNT(DISTINCT f.entidad_key)     AS entidades,
       SUM(f.valor_contrato)             AS valor
FROM powerbi.fact_contrato AS f
JOIN powerbi.dim_proveedor AS p ON p.proveedor_key = f.proveedor_key
WHERE f.es_valido AND p.tipo_persona = 'Persona jurídica'
GROUP BY 1, 2
ORDER BY valor DESC
LIMIT 100;

CREATE VIEW powerbi_extract.dim_fecha AS
SELECT fecha, mes_num, mes_nombre, anio_mes, trimestre
FROM powerbi.dim_fecha
WHERE anio = 2024;

CREATE VIEW powerbi_extract.dim_entidad AS
SELECT entidad_key, entidad, nit_entidad, sector, orden, departamento_key
FROM powerbi.dim_entidad;

CREATE VIEW powerbi_extract.dim_departamento AS SELECT * FROM powerbi.dim_departamento;
CREATE VIEW powerbi_extract.dim_modalidad   AS SELECT * FROM powerbi.dim_modalidad;
CREATE VIEW powerbi_extract.dim_tipo_persona AS
SELECT DISTINCT tipo_persona FROM powerbi.dim_proveedor;

-- Control: el extracto suma lo mismo que el hecho por contrato.
DO $$
BEGIN
    IF (SELECT SUM(contratos) FROM powerbi_extract.fact_mensual)
           <> (SELECT COUNT(*) FROM powerbi.fact_contrato)
       OR (SELECT SUM(valor) FROM powerbi_extract.fact_mensual)
           <> (SELECT SUM(valor_contrato) FROM powerbi.fact_contrato WHERE es_valido) THEN
        RAISE EXCEPTION 'powerbi_extract: fact_mensual no cuadra con powerbi.fact_contrato';
    END IF;
END $$;
