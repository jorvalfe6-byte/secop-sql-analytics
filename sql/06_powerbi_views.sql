-- =====================================================================
-- 06_powerbi_views.sql — Esquema `powerbi`: modelo en estrella listo para
-- importar en Power BI (Obtener datos → PostgreSQL → esquema powerbi).
--
--   dim_fecha ─────┐
--   dim_entidad ───┤
--   dim_proveedor ─┼──▶ fact_contrato   (grano: UN contrato = una fila)
--   dim_departamento ┤
--   dim_modalidad ──┘
--
-- Reglas del modelo:
--   * Claves enteras (fecha_key = AAAAMMDD) o de texto corto (proveedor_key).
--   * Relaciones uno a muchos desde cada dimensión hacia el hecho, con filtro
--     en un solo sentido. Cada clave del hecho existe en su dimensión.
--   * dim_fecha es un calendario continuo, sin huecos. Las fechas de inicio y fin
--     son relaciones adicionales (inactivas en Power BI) hacia la misma dimensión.
--   * El hecho trae TODOS los contratos y la columna `es_valido`. Para sumar dinero
--     hay que filtrar es_valido = TRUE (ver mart.fact_contrato).
--   * El departamento es el de la entidad que contrata, no el de ejecución.
--   * Privacidad: en dim_proveedor, las personas naturales NO llevan nombre ni
--     documento; solo el tipo de persona. Las personas jurídicas llevan razón
--     social y NIT, que son públicos.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP SCHEMA IF EXISTS powerbi CASCADE;
CREATE SCHEMA powerbi;

-- ---------------------------------------------------------------------
-- dim_fecha — calendario continuo desde el 1 de enero del año de la primera firma
-- hasta el 31 de diciembre del año de la última fecha de fin coherente (tope: firma + 10 años).
-- ---------------------------------------------------------------------
CREATE VIEW powerbi.dim_fecha AS
WITH rango AS (
    SELECT DATE_TRUNC('year', MIN(firmado_en))::DATE                                  AS desde,
           (DATE_TRUNC('year', GREATEST(MAX(firmado_en),
                  COALESCE(MAX(fin_en) FILTER (WHERE fin_en < firmado_en + INTERVAL '10 years'
                                                 AND fin_en >= firmado_en), MAX(firmado_en))))
            + INTERVAL '1 year - 1 day')::DATE                                        AS hasta
    FROM mart.fact_contrato
)
SELECT TO_CHAR(d, 'YYYYMMDD')::INT                                   AS fecha_key,
       d::DATE                                                       AS fecha,
       EXTRACT(YEAR FROM d)::INT                                     AS anio,
       EXTRACT(QUARTER FROM d)::INT                                  AS trimestre,
       EXTRACT(MONTH FROM d)::INT                                    AS mes_num,
       (ARRAY['enero','febrero','marzo','abril','mayo','junio','julio','agosto',
              'septiembre','octubre','noviembre','diciembre'])[EXTRACT(MONTH FROM d)::INT] AS mes_nombre,
       TO_CHAR(d, 'YYYY-MM')                                         AS anio_mes,
       DATE_TRUNC('month', d)::DATE                                  AS mes_inicio,
       EXTRACT(ISODOW FROM d)::INT                                   AS dia_semana_num,
       (ARRAY['lunes','martes','miércoles','jueves','viernes','sábado','domingo'])[EXTRACT(ISODOW FROM d)::INT] AS dia_semana,
       (EXTRACT(ISODOW FROM d) >= 6)                                 AS es_fin_de_semana
FROM rango, GENERATE_SERIES(rango.desde, rango.hasta, INTERVAL '1 day') AS d;

-- ---------------------------------------------------------------------
-- dim_departamento — con código DANE para mapas
-- ---------------------------------------------------------------------
CREATE VIEW powerbi.dim_departamento AS
WITH nombres AS (SELECT DISTINCT departamento FROM core.entidad),
dane (departamento, codigo_dane) AS (VALUES
    ('Antioquia','05'),('Atlántico','08'),('Distrito Capital de Bogotá','11'),('Bolívar','13'),('Boyacá','15'),
    ('Caldas','17'),('Caquetá','18'),('Cauca','19'),('Cesar','20'),('Córdoba','23'),('Cundinamarca','25'),
    ('Chocó','27'),('Huila','41'),('La Guajira','44'),('Magdalena','47'),('Meta','50'),('Nariño','52'),
    ('Norte de Santander','54'),('Quindío','63'),('Risaralda','66'),('Santander','68'),('Sucre','70'),
    ('Tolima','73'),('Valle del Cauca','76'),('Arauca','81'),('Casanare','85'),('Putumayo','86'),
    ('San Andrés, Providencia y Santa Catalina','88'),('Amazonas','91'),('Guainía','94'),('Guaviare','95'),
    ('Vaupés','97'),('Vichada','99'))
SELECT ROW_NUMBER() OVER (ORDER BY n.departamento)::INT AS departamento_key,
       n.departamento,
       d.codigo_dane
FROM nombres AS n LEFT JOIN dane AS d USING (departamento);

-- ---------------------------------------------------------------------
-- dim_entidad
-- ---------------------------------------------------------------------
CREATE VIEW powerbi.dim_entidad AS
SELECT e.entidad_id               AS entidad_key,
       e.nombre                   AS entidad,
       e.nit                      AS nit_entidad,
       e.sector,
       e.orden,
       e.rama,
       e.centralizada,
       e.ciudad,
       d.departamento_key
FROM core.entidad AS e
JOIN powerbi.dim_departamento AS d ON d.departamento = e.departamento;

-- ---------------------------------------------------------------------
-- dim_proveedor — fila 'sin proveedor' con clave '0' para los contratos sin código
-- ---------------------------------------------------------------------
CREATE VIEW powerbi.dim_proveedor AS
SELECT '0'::TEXT                  AS proveedor_key,
       'Sin proveedor identificado' AS proveedor,
       'Sin proveedor'            AS tipo_persona,
       NULL::TEXT                 AS nit_proveedor
UNION ALL
SELECT p.proveedor_id,
       CASE WHEN p.tipo_documento = 'NIT' THEN p.nombre
            ELSE 'Persona natural' END,
       CASE WHEN p.tipo_documento = 'NIT' THEN 'Persona jurídica'
            WHEN p.tipo_documento ILIKE 'Cédula%' OR p.tipo_documento ILIKE 'Permiso%'
              OR p.tipo_documento ILIKE 'Pasaporte%' THEN 'Persona natural'
            ELSE 'Otro documento' END,
       CASE WHEN p.tipo_documento = 'NIT' THEN p.documento END
FROM core.proveedor AS p;

-- ---------------------------------------------------------------------
-- dim_modalidad
-- ---------------------------------------------------------------------
CREATE VIEW powerbi.dim_modalidad AS
SELECT ROW_NUMBER() OVER (ORDER BY modalidad_grupo, modalidad)::INT AS modalidad_key,
       modalidad,
       modalidad_grupo
FROM (SELECT DISTINCT COALESCE(modalidad, 'Sin modalidad') AS modalidad, modalidad_grupo
      FROM mart.fact_contrato) AS t;

-- ---------------------------------------------------------------------
-- fact_contrato — grano: un contrato (id_contrato)
-- ---------------------------------------------------------------------
CREATE VIEW powerbi.fact_contrato AS
SELECT f.id_contrato,
       TO_CHAR(f.firmado_en, 'YYYYMMDD')::INT                    AS fecha_firma_key,
       -- inicio y fin: solo si son coherentes y caen dentro del calendario (si no, NULL)
       CASE WHEN NOT f.f_fechas_imposibles THEN di.fecha_key END  AS fecha_inicio_key,
       CASE WHEN NOT f.f_fechas_imposibles THEN dfn.fecha_key END AS fecha_fin_key,
       f.entidad_id                                              AS entidad_key,
       COALESCE(f.proveedor_id, '0')                             AS proveedor_key,
       dd.departamento_key,
       dm.modalidad_key,
       f.tipo_contrato,
       f.estado,
       f.valor_contrato,
       f.valor_pagado,
       f.valor_facturado,
       f.duracion_dias,
       f.dias_adicionados,
       f.is_valid                                                AS es_valido,
       f.f_valor_cero                                            AS valor_cero,
       f.f_fechas_imposibles                                     AS fechas_imposibles,
       f.f_pagado_excede                                         AS pagado_excede
FROM mart.fact_contrato AS f
JOIN core.entidad AS e                ON e.entidad_id = f.entidad_id
LEFT JOIN powerbi.dim_fecha AS di     ON di.fecha = f.inicio_en::DATE
LEFT JOIN powerbi.dim_fecha AS dfn    ON dfn.fecha = f.fin_en::DATE
JOIN powerbi.dim_departamento AS dd   ON dd.departamento = e.departamento
JOIN powerbi.dim_modalidad AS dm      ON dm.modalidad = COALESCE(f.modalidad, 'Sin modalidad')
                                     AND dm.modalidad_grupo = f.modalidad_grupo;

COMMENT ON VIEW powerbi.fact_contrato IS 'Grano: un contrato. Filtrar es_valido = TRUE para sumar dinero.';
