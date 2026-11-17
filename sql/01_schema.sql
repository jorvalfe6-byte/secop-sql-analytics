-- =====================================================================
-- 01_schema.sql — Modelo relacional SECOP II (PostgreSQL 14+)
--
-- Capas:
--   staging : copia 1:1 de los CSV, todo TEXT. Nunca falla por tipos.
--   core    : modelo tipado con PK, FK y CHECK (ver 02_core_tables.sql).
--   mart    : vistas analíticas (ver 04_marts.sql).
--   audit   : bitácora de cada carga.
--   powerbi : estrella para Power BI (ver 06_powerbi_views.sql).
--
-- Las fechas del dataset no traen zona horaria (hora local de Colombia),
-- por eso se usa TIMESTAMP y no TIMESTAMPTZ.
-- =====================================================================

SET client_min_messages = warning;  -- silencia los avisos de DROP ... CASCADE

DROP SCHEMA IF EXISTS powerbi CASCADE;
DROP SCHEMA IF EXISTS mart    CASCADE;
DROP SCHEMA IF EXISTS core    CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS audit   CASCADE;

CREATE SCHEMA staging;
CREATE SCHEMA core;
CREATE SCHEMA mart;
CREATE SCHEMA audit;
CREATE SCHEMA powerbi;

-- ---------------------------------------------------------------------
-- audit
-- ---------------------------------------------------------------------
CREATE TABLE audit.load_log (
    load_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name     TEXT        NOT NULL,
    rows_staged    BIGINT      NOT NULL,
    rows_loaded    BIGINT      NOT NULL,
    rows_rejected  BIGINT      GENERATED ALWAYS AS (rows_staged - rows_loaded) STORED,
    note           TEXT,
    loaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- staging: mismas columnas y orden que los CSV de la API
-- ---------------------------------------------------------------------
CREATE TABLE staging.contratos (
    nombre_entidad TEXT, nit_entidad TEXT, codigo_entidad TEXT, departamento TEXT, ciudad TEXT,
    orden TEXT, sector TEXT, rama TEXT, entidad_centralizada TEXT, proceso_de_compra TEXT,
    id_contrato TEXT, referencia_del_contrato TEXT, estado_contrato TEXT,
    codigo_de_categoria_principal TEXT, tipo_de_contrato TEXT, modalidad_de_contratacion TEXT,
    justificacion_modalidad_de TEXT, fecha_de_firma TEXT, fecha_de_inicio_del_contrato TEXT,
    fecha_de_fin_del_contrato TEXT, duraci_n_del_contrato TEXT, tipodocproveedor TEXT,
    documento_proveedor TEXT, codigo_proveedor TEXT, proveedor_adjudicado TEXT, es_grupo TEXT,
    es_pyme TEXT, habilita_pago_adelantado TEXT, liquidaci_n TEXT,
    el_contrato_puede_ser_prorrogado TEXT, origen_de_los_recursos TEXT, destino_gasto TEXT,
    valor_del_contrato TEXT, valor_de_pago_adelantado TEXT, valor_facturado TEXT,
    valor_pendiente_de_pago TEXT, valor_pagado TEXT, dias_adicionados TEXT, ultima_actualizacion TEXT
);

-- Control de la descarga: filas que devolvió la API por mes de firma
-- (lo escribe download_data.sh en data/_conteo_api.csv).
CREATE TABLE staging.conteo_api (
    mes TEXT, filas_api TEXT
);

-- ---------------------------------------------------------------------
-- helpers de conversión: un valor ilegible da NULL en vez de tumbar la carga
-- ---------------------------------------------------------------------
CREATE FUNCTION core.try_ts(t TEXT) RETURNS TIMESTAMP
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF t IS NULL OR t = '' THEN RETURN NULL; END IF;
    RETURN t::TIMESTAMP;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END $$;

CREATE FUNCTION core.try_num(t TEXT) RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    IF t IS NULL OR t = '' THEN RETURN NULL; END IF;
    RETURN t::NUMERIC;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END $$;

-- texto vacío o 'No Definido' (centinela de la fuente, con mayúsculas variables) → 'No definido'
CREATE FUNCTION core.limpia(t TEXT) RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN t IS NULL OR TRIM(t) = '' OR LOWER(TRIM(t)) = 'no definido' THEN 'No definido' ELSE TRIM(t) END
$$;
