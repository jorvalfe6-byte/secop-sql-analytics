-- =====================================================================
-- 00_calidad_datos.sql — Controles de calidad después de cada carga.
-- Cada fila es un control: 'OK' o 'REVISAR' con el valor encontrado.
--
-- Esta carga no tiene totales fijos para comparar (el dataset de SECOP se
-- actualiza en el origen), así que los controles se apoyan en dos cosas:
--   * el conteo por mes que dio la API al descargar (data/_conteo_api.csv);
--   * invariantes de integridad que siempre deben cumplirse.
-- Los problemas de CALIDAD de la fuente (valores en cero, fechas imposibles,
-- NIT inválidos) no son errores de carga: se miden en 08_calidad_hallazgos.sql.
-- =====================================================================
WITH controles AS (
    -- 1. Cada mes de staging trae las filas que dijo la API
    SELECT 'meses de staging que coinciden con el conteo de la API' AS control,
           (SELECT COUNT(*) FROM staging.conteo_api AS a
             WHERE a.filas_api::BIGINT = (SELECT COUNT(*) FROM staging.contratos AS s
                                          WHERE TO_CHAR(core.try_ts(s.fecha_de_firma), 'YYYYMM') = a.mes)) AS valor,
           (SELECT COUNT(*) FROM staging.conteo_api)                AS esperado
    UNION ALL
    SELECT 'filas en staging vs. suma del conteo de la API',
           (SELECT COUNT(*) FROM staging.contratos),
           (SELECT SUM(filas_api::BIGINT) FROM staging.conteo_api)
    UNION ALL
    -- 2. Nada se cayó sin explicación: leídas = cargadas + repetidas + ilegibles
    SELECT 'filas rechazadas por id, entidad, firma o valor ilegible',
           (SELECT COALESCE(SUM(SUBSTRING(note FROM 'sin id_contrato: ([0-9]+)')::BIGINT
                             + SUBSTRING(note FROM 'sin codigo_entidad: ([0-9]+)')::BIGINT
                             + SUBSTRING(note FROM 'firma o valor ilegible: ([0-9]+)')::BIGINT), 0)
            FROM audit.load_log
            WHERE table_name = 'core.contrato'
              AND loaded_at = (SELECT MAX(loaded_at) FROM audit.load_log)),
           0
    UNION ALL
    SELECT 'contratos cargados + versiones repetidas = filas leídas',
           (SELECT COUNT(*) FROM core.contrato)
             + (SELECT COUNT(*) FROM staging.contratos) - (SELECT COUNT(DISTINCT id_contrato) FROM staging.contratos),
           (SELECT COUNT(*) FROM staging.contratos)
    UNION ALL
    -- 3. Dinero: la suma del core es la de staging quedándose con una versión por contrato
    SELECT 'valor total en core vs. staging deduplicado (pesos)',
           (SELECT SUM(valor_contrato)::BIGINT FROM core.contrato),
           (SELECT SUM(core.try_num(valor_del_contrato))::BIGINT FROM (
                SELECT DISTINCT ON (id_contrato) valor_del_contrato
                FROM staging.contratos
                ORDER BY id_contrato, core.try_ts(ultima_actualizacion) DESC NULLS LAST,
                         core.try_ts(fecha_de_firma) DESC, core.try_num(valor_del_contrato) DESC) AS d)
    UNION ALL
    -- 4. Período: todo contrato firmado dentro de los meses descargados
    SELECT 'contratos firmados fuera de los meses descargados',
           (SELECT COUNT(*) FROM core.contrato
             WHERE TO_CHAR(firmado_en, 'YYYYMM') NOT IN (SELECT mes FROM staging.conteo_api)), 0
    UNION ALL
    -- 5. Integridad que las FK no cubren
    SELECT 'id_contrato repetidos en core',
           (SELECT COUNT(*) - COUNT(DISTINCT id_contrato) FROM core.contrato), 0
    UNION ALL
    SELECT 'contratos sin entidad en core',
           (SELECT COUNT(*) FROM core.contrato AS c LEFT JOIN core.entidad AS e USING (entidad_id)
             WHERE e.entidad_id IS NULL), 0
    UNION ALL
    SELECT 'proveedores en core sin ningún contrato',
           (SELECT COUNT(*) FROM core.proveedor AS p
             WHERE NOT EXISTS (SELECT 1 FROM core.contrato AS c WHERE c.proveedor_id = p.proveedor_id)), 0
    UNION ALL
    SELECT 'entidades en core sin ningún contrato',
           (SELECT COUNT(*) FROM core.entidad AS e
             WHERE NOT EXISTS (SELECT 1 FROM core.contrato AS c WHERE c.entidad_id = e.entidad_id)), 0
    UNION ALL
    -- 6. La vista del mart no pierde ni duplica contratos
    SELECT 'contratos en mart.fact_contrato vs. core',
           (SELECT COUNT(*) FROM mart.fact_contrato), (SELECT COUNT(*) FROM core.contrato)
    UNION ALL
    SELECT 'contratos válidos + inválidos = total',
           (SELECT COUNT(*) FILTER (WHERE is_valid) + COUNT(*) FILTER (WHERE NOT is_valid) FROM mart.fact_contrato),
           (SELECT COUNT(*) FROM mart.fact_contrato)
    UNION ALL
    -- 7. Esquema powerbi: grano único, claves completas y calendario continuo
    SELECT 'powerbi.fact_contrato vs. core (filas)',
           (SELECT COUNT(*) FROM powerbi.fact_contrato), (SELECT COUNT(*) FROM core.contrato)
    UNION ALL
    SELECT 'powerbi: id_contrato repetidos en el hecho',
           (SELECT COUNT(*) - COUNT(DISTINCT id_contrato) FROM powerbi.fact_contrato), 0
    UNION ALL
    SELECT 'powerbi: claves del hecho sin fila en su dimensión',
           (SELECT COUNT(*) FROM powerbi.fact_contrato AS f
             WHERE NOT EXISTS (SELECT 1 FROM powerbi.dim_fecha AS d WHERE d.fecha_key = f.fecha_firma_key)
                OR (f.fecha_inicio_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM powerbi.dim_fecha AS d WHERE d.fecha_key = f.fecha_inicio_key))
                OR (f.fecha_fin_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM powerbi.dim_fecha AS d WHERE d.fecha_key = f.fecha_fin_key))
                OR NOT EXISTS (SELECT 1 FROM powerbi.dim_entidad AS d WHERE d.entidad_key = f.entidad_key)
                OR NOT EXISTS (SELECT 1 FROM powerbi.dim_proveedor AS d WHERE d.proveedor_key = f.proveedor_key)
                OR NOT EXISTS (SELECT 1 FROM powerbi.dim_departamento AS d WHERE d.departamento_key = f.departamento_key)
                OR NOT EXISTS (SELECT 1 FROM powerbi.dim_modalidad AS d WHERE d.modalidad_key = f.modalidad_key)), 0
    UNION ALL
    SELECT 'powerbi: días del calendario vs. días del rango (sin huecos)',
           (SELECT COUNT(*) FROM powerbi.dim_fecha),
           (SELECT MAX(fecha) - MIN(fecha) + 1 FROM powerbi.dim_fecha)
    UNION ALL
    SELECT 'powerbi: valor total del hecho vs. core (pesos)',
           (SELECT SUM(valor_contrato)::BIGINT FROM powerbi.fact_contrato), (SELECT SUM(valor_contrato)::BIGINT FROM core.contrato)
)
SELECT control,
       valor,
       esperado,
       CASE WHEN valor = esperado THEN 'OK' ELSE 'REVISAR' END AS estado
FROM controles;
