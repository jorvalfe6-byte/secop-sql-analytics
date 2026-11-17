-- =====================================================================
-- 03_transform.sql — staging → core, en una sola transacción.
-- Idempotente: vacía core y lo vuelve a poblar. Cada tabla deja su
-- registro en audit.load_log (filas leídas vs. cargadas).
--
-- Qué se hace aquí y qué no:
--   * Se descartan solo (a) filas sin id_contrato, sin fecha de firma legible o
--     sin valor numérico, y (b) versiones repetidas del mismo id_contrato
--     (se conserva la de última actualización).
--   * Los valores dudosos (valor cero, fechas imposibles, NIT raros) NO se borran:
--     se cargan tal cual y se marcan en mart.fact_contrato.
--   * Los centinelas de la fuente ('No Definido') se vuelven NULL donde NULL
--     tiene sentido (proveedor sin código) o se unifican como 'No definido'.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

TRUNCATE core.contrato, core.proveedor, core.entidad;

-- ---------------------------------------------------------------------
-- Staging depurado: tipos básicos y una sola versión por contrato.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE t_leidas ON COMMIT DROP AS
SELECT s.*,
       core.try_ts(fecha_de_firma)       AS firmado_en,
       core.try_ts(ultima_actualizacion) AS actualizado_en,
       core.try_num(valor_del_contrato)  AS valor_num,
       (NULLIF(TRIM(id_contrato), '') IS NULL)                    AS sin_id,
       (codigo_entidad !~ '^[0-9]{1,18}$')                        AS sin_entidad
FROM staging.contratos AS s;

CREATE TEMP TABLE t_contrato ON COMMIT DROP AS
SELECT * FROM (
    SELECT l.*,
           ROW_NUMBER() OVER (PARTITION BY id_contrato
                              ORDER BY actualizado_en DESC NULLS LAST, firmado_en DESC,
                                       valor_num DESC) AS rn
    FROM t_leidas AS l
    WHERE NOT sin_id AND NOT sin_entidad AND firmado_en IS NOT NULL AND valor_num IS NOT NULL
) AS x
WHERE rn = 1;

CREATE UNIQUE INDEX ON t_contrato (id_contrato);

-- ---------------------------------------------------------------------
-- entidad: el atributo más frecuente por codigo_entidad (la fuente repite
-- el nombre y la ubicación en cada contrato y a veces no coinciden).
-- ---------------------------------------------------------------------
INSERT INTO core.entidad (entidad_id, nit, nombre, departamento, ciudad, orden, sector, rama, centralizada)
SELECT codigo_entidad::BIGINT,
       mode() WITHIN GROUP (ORDER BY TRIM(nit_entidad)),
       mode() WITHIN GROUP (ORDER BY TRIM(nombre_entidad)),
       mode() WITHIN GROUP (ORDER BY core.limpia(departamento)),
       mode() WITHIN GROUP (ORDER BY core.limpia(ciudad)),
       mode() WITHIN GROUP (ORDER BY core.limpia(orden)),
       mode() WITHIN GROUP (ORDER BY CASE WHEN TRIM(sector) = LOWER(TRIM(sector)) AND LOWER(TRIM(sector)) <> 'no definido' AND TRIM(sector) <> ''
                                          THEN UPPER(LEFT(TRIM(sector), 1)) || SUBSTR(TRIM(sector), 2)
                                          ELSE core.limpia(sector) END),
       mode() WITHIN GROUP (ORDER BY core.limpia(rama)),
       mode() WITHIN GROUP (ORDER BY core.limpia(entidad_centralizada))
FROM t_contrato
GROUP BY codigo_entidad::BIGINT;

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded, note)
SELECT 'core.entidad',
       (SELECT COUNT(DISTINCT codigo_entidad) FROM t_contrato),
       (SELECT COUNT(*) FROM core.entidad),
       'entidades distintas por codigo_entidad; atributos = valor más frecuente';

-- ---------------------------------------------------------------------
-- proveedor
-- ---------------------------------------------------------------------
INSERT INTO core.proveedor (proveedor_id, tipo_documento, documento, nombre)
SELECT TRIM(codigo_proveedor),
       mode() WITHIN GROUP (ORDER BY core.limpia(tipodocproveedor)),
       mode() WITHIN GROUP (ORDER BY core.limpia(documento_proveedor)),
       mode() WITHIN GROUP (ORDER BY core.limpia(proveedor_adjudicado))
FROM t_contrato
WHERE NULLIF(TRIM(codigo_proveedor), '') IS NOT NULL
  AND LOWER(TRIM(codigo_proveedor)) NOT IN ('no definido', 'no aplica')
GROUP BY TRIM(codigo_proveedor);

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded, note)
SELECT 'core.proveedor',
       (SELECT COUNT(DISTINCT TRIM(codigo_proveedor)) FROM t_contrato
         WHERE NULLIF(TRIM(codigo_proveedor), '') IS NOT NULL
           AND LOWER(TRIM(codigo_proveedor)) NOT IN ('no definido', 'no aplica')),
       (SELECT COUNT(*) FROM core.proveedor),
       'contratos sin código de proveedor quedan con proveedor_id NULL';

-- ---------------------------------------------------------------------
-- contrato
-- ---------------------------------------------------------------------
INSERT INTO core.contrato (
    id_contrato, proceso_de_compra, referencia, entidad_id, proveedor_id, estado, categoria_codigo,
    tipo_contrato, modalidad, justificacion, firmado_en, inicio_en, fin_en, duracion_texto,
    es_grupo, es_pyme, pago_adelantado, liquidacion, prorrogable, origen_recursos, destino_gasto,
    valor_contrato, valor_pago_adelantado, valor_facturado, valor_pendiente_pago, valor_pagado,
    dias_adicionados, actualizado_en)
SELECT TRIM(t.id_contrato),
       NULLIF(TRIM(t.proceso_de_compra), ''),
       NULLIF(TRIM(t.referencia_del_contrato), ''),
       t.codigo_entidad::BIGINT,
       p.proveedor_id,
       NULLIF(TRIM(t.estado_contrato), ''),
       NULLIF(TRIM(t.codigo_de_categoria_principal), ''),
       NULLIF(TRIM(t.tipo_de_contrato), ''),
       NULLIF(TRIM(t.modalidad_de_contratacion), ''),
       NULLIF(TRIM(t.justificacion_modalidad_de), ''),
       t.firmado_en,
       core.try_ts(t.fecha_de_inicio_del_contrato),
       core.try_ts(t.fecha_de_fin_del_contrato),
       NULLIF(TRIM(t.duraci_n_del_contrato), ''),
       CASE WHEN LOWER(t.es_grupo) IN ('si', 'sí') THEN TRUE WHEN LOWER(t.es_grupo) = 'no' THEN FALSE END,
       CASE WHEN LOWER(t.es_pyme) IN ('si', 'sí') THEN TRUE WHEN LOWER(t.es_pyme) = 'no' THEN FALSE END,
       CASE WHEN LOWER(t.habilita_pago_adelantado) IN ('si', 'sí') THEN TRUE WHEN LOWER(t.habilita_pago_adelantado) = 'no' THEN FALSE END,
       CASE WHEN LOWER(t.liquidaci_n) IN ('si', 'sí') THEN TRUE WHEN LOWER(t.liquidaci_n) = 'no' THEN FALSE END,
       CASE WHEN LOWER(t.el_contrato_puede_ser_prorrogado) IN ('si', 'sí') THEN TRUE WHEN LOWER(t.el_contrato_puede_ser_prorrogado) = 'no' THEN FALSE END,
       NULLIF(TRIM(t.origen_de_los_recursos), ''),
       NULLIF(TRIM(t.destino_gasto), ''),
       t.valor_num,
       core.try_num(t.valor_de_pago_adelantado),
       core.try_num(t.valor_facturado),
       core.try_num(t.valor_pendiente_de_pago),
       core.try_num(t.valor_pagado),
       core.try_num(t.dias_adicionados)::INTEGER,
       t.actualizado_en
FROM t_contrato AS t
LEFT JOIN core.proveedor AS p ON p.proveedor_id = TRIM(t.codigo_proveedor);

-- ---------------------------------------------------------------------
-- auditoría de la tabla principal: leídas vs. cargadas, y por qué se cayó cada una
-- ---------------------------------------------------------------------
INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded, note)
SELECT 'core.contrato',
       (SELECT COUNT(*) FROM t_leidas),
       (SELECT COUNT(*) FROM core.contrato),
       'sin id_contrato: '                || (SELECT COUNT(*) FROM t_leidas WHERE sin_id)
    || ' · sin codigo_entidad: '          || (SELECT COUNT(*) FROM t_leidas WHERE NOT sin_id AND sin_entidad)
    || ' · firma o valor ilegible: '      || (SELECT COUNT(*) FROM t_leidas
                                               WHERE NOT sin_id AND NOT sin_entidad
                                                 AND (firmado_en IS NULL OR valor_num IS NULL))
    || ' · versiones repetidas: '         || ((SELECT COUNT(*) FROM t_leidas
                                                WHERE NOT sin_id AND NOT sin_entidad
                                                  AND firmado_en IS NOT NULL AND valor_num IS NOT NULL)
                                              - (SELECT COUNT(*) FROM t_contrato));

COMMIT;

CREATE INDEX IF NOT EXISTS ix_contrato_entidad   ON core.contrato (entidad_id);
CREATE INDEX IF NOT EXISTS ix_contrato_proveedor ON core.contrato (proveedor_id);
CREATE INDEX IF NOT EXISTS ix_contrato_firma     ON core.contrato (firmado_en);
CREATE INDEX IF NOT EXISTS ix_contrato_modalidad ON core.contrato (modalidad);
ANALYZE;
