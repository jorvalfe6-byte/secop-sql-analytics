-- =====================================================================
-- 05_dashboard_views.sql — Vistas compactas que alimentan el dashboard.
-- Cada una es la versión resumida de una consulta de sql/analysis/.
-- scripts/export_dashboard.sh las vuelca a docs/data/dashboard.json.
--
-- Privacidad: solo agregados. La única excepción son los 10 mayores
-- proveedores, y únicamente personas jurídicas (NIT): una persona natural
-- nunca aparece con nombre.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP VIEW IF EXISTS mart.dash_kpis, mart.dash_mensual, mart.dash_departamentos, mart.dash_sectores,
                    mart.dash_top_entidades, mart.dash_top_proveedores, mart.dash_concentracion,
                    mart.dash_modalidades, mart.dash_grupos_modalidad, mart.dash_duracion,
                    mart.dash_ejecucion, mart.dash_calidad CASCADE;

-- KPIs generales (ver analysis/01)
CREATE VIEW mart.dash_kpis AS
SELECT (SELECT COUNT(*) FROM mart.fact_contrato)                                       AS contratos_total,
       COUNT(*)                                                                         AS contratos,
       ROUND(SUM(valor_contrato), 0)                                                    AS valor,
       COUNT(DISTINCT entidad_id)                                                       AS entidades,
       COUNT(DISTINCT proveedor_id)                                                     AS proveedores,
       ROUND(100.0 * SUM(valor_contrato) FILTER (WHERE modalidad_grupo = 'Contratación directa')
                   / SUM(valor_contrato), 1)                                            AS pct_directa_valor,
       ROUND(100.0 * SUM(valor_contrato) FILTER (WHERE modalidad_grupo = 'Competitiva')
                   / SUM(valor_contrato), 1)                                            AS pct_competitiva_valor,
       (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duracion_dias)
            FILTER (WHERE duracion_dias IS NOT NULL))::INT                              AS mediana_duracion_dias,
       MIN(firmado_en)::DATE                                                            AS desde,
       MAX(firmado_en)::DATE                                                            AS hasta
FROM mart.fact_contrato
WHERE is_valid;

-- Valor por mes de firma (ver analysis/02)
CREATE VIEW mart.dash_mensual AS
WITH calendario AS (
    SELECT generate_series(MIN(mes_firma), MAX(mes_firma), INTERVAL '1 month')::DATE AS mes
    FROM mart.fact_contrato
),
mensual AS (
    SELECT mes_firma AS mes, COUNT(*) AS contratos, SUM(valor_contrato) AS valor
    FROM mart.fact_contrato WHERE is_valid GROUP BY mes_firma
)
SELECT c.mes,
       COALESCE(m.contratos, 0)       AS contratos,
       ROUND(COALESCE(m.valor, 0), 0) AS valor,
       ROUND(AVG(COALESCE(m.valor, 0)) OVER (ORDER BY c.mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS valor_mm3
FROM calendario AS c LEFT JOIN mensual AS m USING (mes);

-- Departamentos y sectores (ver analysis/03)
CREATE VIEW mart.dash_departamentos AS
SELECT e.departamento,
       COUNT(*)                                                          AS contratos,
       ROUND(SUM(f.valor_contrato), 0)                                   AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) / SUM(SUM(f.valor_contrato)) OVER (), 2) AS pct_valor,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.valor_contrato)::NUMERIC, 0) AS valor_mediano
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
WHERE f.is_valid
GROUP BY e.departamento;

CREATE VIEW mart.dash_sectores AS
SELECT e.sector,
       COUNT(*)                                                          AS contratos,
       ROUND(SUM(f.valor_contrato), 0)                                   AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) / SUM(SUM(f.valor_contrato)) OVER (), 2) AS pct_valor
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
WHERE f.is_valid
GROUP BY e.sector;

-- Top entidades y proveedores (ver analysis/04)
CREATE VIEW mart.dash_top_entidades AS
SELECT ROW_NUMBER() OVER (ORDER BY SUM(f.valor_contrato) DESC, e.entidad_id) AS ranking,
       e.nombre                                                          AS entidad,
       e.sector,
       COUNT(*)                                                          AS contratos,
       ROUND(SUM(f.valor_contrato), 0)                                   AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) / SUM(SUM(f.valor_contrato)) OVER (), 2) AS pct_valor,
       ROUND(100.0 * SUM(f.valor_contrato) FILTER (WHERE f.modalidad_grupo = 'Contratación directa')
                   / SUM(f.valor_contrato), 1)                           AS pct_directa
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
WHERE f.is_valid
GROUP BY e.entidad_id, e.nombre, e.sector
ORDER BY valor DESC
LIMIT 10;

CREATE VIEW mart.dash_top_proveedores AS
SELECT ROW_NUMBER() OVER (ORDER BY SUM(f.valor_contrato) DESC, p.proveedor_id) AS ranking,
       p.nombre                                                          AS proveedor,
       COUNT(*)                                                          AS contratos,
       COUNT(DISTINCT f.entidad_id)                                      AS entidades,
       ROUND(SUM(f.valor_contrato), 0)                                   AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) / (SELECT SUM(valor_contrato) FROM mart.fact_contrato WHERE is_valid), 2) AS pct_valor
FROM mart.fact_contrato AS f JOIN core.proveedor AS p USING (proveedor_id)
WHERE f.is_valid AND f.proveedor_tipo = 'Persona jurídica'
GROUP BY p.proveedor_id, p.nombre
ORDER BY valor DESC
LIMIT 10;

-- Curva de Pareto de proveedores y entidades (ver analysis/04)
CREATE VIEW mart.dash_concentracion AS
WITH por_actor AS (
    SELECT 'proveedores' AS actor, proveedor_id AS id, SUM(valor_contrato) AS valor
    FROM mart.fact_contrato WHERE is_valid AND proveedor_id IS NOT NULL GROUP BY proveedor_id
    UNION ALL
    SELECT 'entidades', entidad_id::TEXT, SUM(valor_contrato)
    FROM mart.fact_contrato WHERE is_valid GROUP BY entidad_id
),
ordenado AS (
    SELECT actor, id, valor,
           ROW_NUMBER() OVER (PARTITION BY actor ORDER BY valor DESC, id) AS pos,
           COUNT(*)     OVER (PARTITION BY actor)                          AS n,
           SUM(valor)   OVER (PARTITION BY actor ORDER BY valor DESC, id)  AS acumulado,
           SUM(valor)   OVER (PARTITION BY actor)                          AS total
    FROM por_actor
),
puntos AS (SELECT p FROM (VALUES (1),(2),(5),(10),(20),(30),(40),(50),(60),(70),(80),(90),(100)) AS v (p))
SELECT o.actor,
       p.p                                           AS pct_actores,
       MAX(o.pos)                                    AS actores_top,
       ROUND(100.0 * MAX(o.acumulado) / MAX(o.total), 1) AS pct_valor,
       CASE WHEN o.actor = 'proveedores' THEN 1 ELSE 2 END AS orden
FROM ordenado AS o
JOIN puntos AS p ON o.pos <= CEIL(o.n * p.p / 100.0)
GROUP BY o.actor, p.p;

-- Modalidades (ver analysis/05)
CREATE VIEW mart.dash_modalidades AS
SELECT COALESCE(modalidad, 'Sin modalidad')                              AS modalidad,
       modalidad_grupo                                                   AS grupo,
       COUNT(*)                                                          AS contratos,
       ROUND(SUM(valor_contrato), 0)                                     AS valor,
       ROUND(100.0 * SUM(valor_contrato) / SUM(SUM(valor_contrato)) OVER (), 2) AS pct_valor
FROM mart.fact_contrato
WHERE is_valid
GROUP BY modalidad, modalidad_grupo;

CREATE VIEW mart.dash_grupos_modalidad AS
SELECT modalidad_grupo                                                   AS grupo,
       COUNT(*)                                                          AS contratos,
       ROUND(SUM(valor_contrato), 0)                                     AS valor,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                AS pct_contratos,
       ROUND(100.0 * SUM(valor_contrato) / SUM(SUM(valor_contrato)) OVER (), 1) AS pct_valor,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valor_contrato)::NUMERIC, 0) AS valor_mediano,
       CASE modalidad_grupo WHEN 'Contratación directa' THEN 1 WHEN 'Régimen especial' THEN 2
                            WHEN 'Competitiva' THEN 3 ELSE 4 END         AS orden
FROM mart.fact_contrato
WHERE is_valid
GROUP BY modalidad_grupo;

-- Duración (ver analysis/06)
CREATE VIEW mart.dash_duracion AS
WITH t AS (
    SELECT valor_contrato,
           CASE WHEN duracion_dias <= 30  THEN 1 WHEN duracion_dias <= 90  THEN 2 WHEN duracion_dias <= 180 THEN 3
                WHEN duracion_dias <= 365 THEN 4 WHEN duracion_dias <= 730 THEN 5 ELSE 6 END AS orden
    FROM mart.fact_contrato
    WHERE is_valid AND duracion_dias IS NOT NULL
)
SELECT orden,
       CASE orden WHEN 1 THEN 'Hasta 1 mes' WHEN 2 THEN '1 a 3 meses' WHEN 3 THEN '3 a 6 meses'
                  WHEN 4 THEN '6 a 12 meses' WHEN 5 THEN '1 a 2 años' ELSE 'Más de 2 años' END AS tramo,
       COUNT(*)                                                          AS contratos,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                AS pct,
       ROUND(100.0 * SUM(valor_contrato) / SUM(SUM(valor_contrato)) OVER (), 1) AS pct_valor
FROM t
GROUP BY orden;

-- Ejecución y adiciones (ver analysis/07)
CREATE VIEW mart.dash_ejecucion AS
SELECT ROUND(SUM(valor_contrato), 0)                                     AS valor_contratado,
       ROUND(SUM(LEAST(COALESCE(valor_pagado, 0), valor_contrato)), 0)   AS valor_pagado,
       ROUND(100.0 * SUM(LEAST(COALESCE(valor_pagado, 0), valor_contrato)) / SUM(valor_contrato), 1) AS pct_pagado,
       COUNT(*) FILTER (WHERE dias_adicionados > 0)                      AS con_dias_adicionados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE dias_adicionados > 0) / COUNT(*), 1) AS pct_con_dias_adicionados,
       COUNT(*) FILTER (WHERE estado = 'Modificado')                     AS modificados,
       ROUND(100.0 * COUNT(*) FILTER (WHERE estado = 'Modificado') / COUNT(*), 1) AS pct_modificado,
       COUNT(*) FILTER (WHERE f_pagado_excede)                           AS pagado_excede
FROM mart.fact_contrato
WHERE is_valid;

-- Calidad de datos (ver analysis/08). Cada fila: cuántos contratos tienen el problema.
CREATE VIEW mart.dash_calidad AS
WITH total AS (SELECT COUNT(*)::NUMERIC AS n FROM mart.fact_contrato),
problemas AS (
    SELECT 1 AS orden, 'Valor del contrato en cero' AS problema,
           COUNT(*) FILTER (WHERE f_valor_cero) AS contratos,
           'valor_contrato = 0' AS criterio,
           'Se marca y se excluye de todo análisis de dinero.' AS tratamiento FROM mart.fact_contrato
    UNION ALL
    SELECT 2, 'Valor menor a $ 1.000', COUNT(*) FILTER (WHERE f_valor_minusculo),
           '0 < valor_contrato < 1.000 COP (menos de un cuarto de dólar)',
           'Se marca y se excluye: no es un contrato real, es una cifra en miles mal digitada o una prueba.' FROM mart.fact_contrato
    UNION ALL
    SELECT 3, 'Valor absurdo (1 billón o más)', COUNT(*) FILTER (WHERE f_valor_absurdo),
           'valor_contrato >= 1e12 COP: ceros de más al digitar',
           'Se marca y se excluye. No se corrige: no hay forma de saber el valor real.' FROM mart.fact_contrato
    UNION ALL
    SELECT 4, 'Sin fecha de inicio o de fin', COUNT(*) FILTER (WHERE f_sin_fechas),
           'inicio o fin vacío', 'Se conserva el contrato; queda fuera del análisis de duración.' FROM mart.fact_contrato
    UNION ALL
    SELECT 5, 'Fechas imposibles', COUNT(*) FILTER (WHERE f_fechas_imposibles),
           'fin antes del inicio o de la firma, o año fuera de 2000–2100',
           'Se conserva el contrato; queda fuera del análisis de duración.' FROM mart.fact_contrato
    UNION ALL
    SELECT 6, 'NIT de la entidad inválido', COUNT(*) FILTER (WHERE f_nit_entidad_invalido),
           'no numérico, de menos de 5 o más de 10 dígitos, o un solo dígito repetido',
           'Se marca. La entidad se identifica por codigo_entidad, no por NIT.' FROM mart.fact_contrato
    UNION ALL
    SELECT 7, 'NIT del proveedor inválido', COUNT(*) FILTER (WHERE f_nit_proveedor_invalido),
           'tipo NIT, no numérico, de menos de 5 o más de 11 dígitos, o un dígito repetido',
           'Se marca. El proveedor se identifica por codigo_proveedor.' FROM mart.fact_contrato
    UNION ALL
    SELECT 8, 'Cédula del proveedor inválida', COUNT(*) FILTER (WHERE f_cedula_invalida),
           'tipo cédula, no numérica, de menos de 5 o más de 11 dígitos, o un dígito repetido',
           'Se marca. No se publica ninguna cédula.' FROM mart.fact_contrato
    UNION ALL
    SELECT 9, 'Sin proveedor identificado', COUNT(*) FILTER (WHERE f_sin_proveedor),
           'codigo_proveedor vacío o «No Definido»',
           'Se conserva el contrato, sin proveedor. Cuenta en valor total pero no en rankings de proveedores.' FROM mart.fact_contrato
    UNION ALL
    SELECT 10, 'Pagado mayor que lo contratado', COUNT(*) FILTER (WHERE f_pagado_excede),
           'valor_pagado > valor_contrato',
           'Se marca. En el indicador de ejecución el pagado se topa en el valor del contrato.' FROM mart.fact_contrato
    UNION ALL
    SELECT 11, 'Posible contrato repetido', COUNT(*) FILTER (WHERE f_posible_repetido),
           'misma entidad, proveedor, valor, referencia y día de firma que otro contrato',
           'Se conserva el de id menor y se excluye el resto de los análisis de dinero.' FROM mart.fact_contrato
    UNION ALL
    SELECT 12, 'Versiones repetidas (eliminadas)',
           COALESCE((SELECT rows_staged - rows_loaded FROM audit.load_log
                      WHERE table_name = 'core.contrato' ORDER BY load_id DESC LIMIT 1), 0)
           - COALESCE((SELECT SUBSTRING(note FROM 'sin id_contrato: ([0-9]+)')::BIGINT
                      + SUBSTRING(note FROM 'sin codigo_entidad: ([0-9]+)')::BIGINT
                      + SUBSTRING(note FROM 'firma o valor ilegible: ([0-9]+)')::BIGINT
                      FROM audit.load_log WHERE table_name = 'core.contrato' ORDER BY load_id DESC LIMIT 1), 0),
           'mismo id_contrato más de una vez en la descarga',
           'Se conserva la versión con ultima_actualizacion más reciente.' FROM (SELECT 1) AS x
)
SELECT orden, problema, contratos, ROUND(100.0 * contratos / total.n, 3) AS pct, criterio, tratamiento
FROM problemas CROSS JOIN total;
