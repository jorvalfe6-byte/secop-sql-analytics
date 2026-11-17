-- =====================================================================
-- 02_core_tables.sql — Tablas tipadas de core (entidad, proveedor, contrato).
-- Se crean vacías; las puebla 03_transform.sql a partir de staging.
-- =====================================================================
\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- core: dimensiones
-- ---------------------------------------------------------------------
-- Grano: una fila por entidad estatal (codigo_entidad de SECOP).
CREATE TABLE core.entidad (
    entidad_id    BIGINT PRIMARY KEY,
    nit           TEXT   NOT NULL,
    nombre        TEXT   NOT NULL,
    departamento  TEXT   NOT NULL,
    ciudad        TEXT   NOT NULL,
    orden         TEXT   NOT NULL,
    sector        TEXT   NOT NULL,
    rama          TEXT   NOT NULL,
    centralizada  TEXT   NOT NULL
);

-- Grano: una fila por proveedor (codigo_proveedor de SECOP).
CREATE TABLE core.proveedor (
    proveedor_id    TEXT PRIMARY KEY,
    tipo_documento  TEXT NOT NULL,
    documento       TEXT NOT NULL,
    nombre          TEXT NOT NULL
);

-- ---------------------------------------------------------------------
-- core: hechos. Grano: una fila por contrato (id_contrato).
-- Aquí se guarda lo que dice la fuente, bien tipado; lo dudoso (valor
-- cero, fechas imposibles, NIT raros) no se borra: se marca en mart.
-- ---------------------------------------------------------------------
CREATE TABLE core.contrato (
    id_contrato           TEXT PRIMARY KEY,
    proceso_de_compra     TEXT,
    referencia            TEXT,
    entidad_id            BIGINT NOT NULL REFERENCES core.entidad (entidad_id),
    proveedor_id          TEXT REFERENCES core.proveedor (proveedor_id),
    estado                TEXT,
    categoria_codigo      TEXT,
    tipo_contrato         TEXT,
    modalidad             TEXT,
    justificacion         TEXT,
    firmado_en            TIMESTAMP NOT NULL,
    inicio_en             TIMESTAMP,
    fin_en                TIMESTAMP,
    duracion_texto        TEXT,
    es_grupo              BOOLEAN,
    es_pyme               BOOLEAN,
    pago_adelantado       BOOLEAN,
    liquidacion           BOOLEAN,
    prorrogable           BOOLEAN,
    origen_recursos       TEXT,
    destino_gasto         TEXT,
    valor_contrato        NUMERIC(22,2) NOT NULL CHECK (valor_contrato >= 0),
    valor_pago_adelantado NUMERIC(22,2),
    valor_facturado       NUMERIC(22,2),
    valor_pendiente_pago  NUMERIC(22,2),
    valor_pagado          NUMERIC(22,2),
    dias_adicionados      INTEGER,
    actualizado_en        TIMESTAMP
);
