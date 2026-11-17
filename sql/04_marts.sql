-- =====================================================================
-- 04_marts.sql — Capa semántica para análisis y dashboards.
--
-- Definiciones de negocio usadas en todo el proyecto:
--   * Contrato válido : valor_contrato de al menos $ 1.000 y menos de 1 billón de
--                       pesos (ver abajo), y que no sea una repetición de otro contrato.
--                       Todo análisis de dinero usa solo estos.
--   * Posible repetido: mismo id distinto pero misma entidad, proveedor, valor,
--                       referencia y día de firma que otro contrato. Se conserva el
--                       de id menor y se marca el resto (id_contrato no se repite
--                       en la fuente, pero el mismo contrato sí aparece con dos ids).
--   * Valor           : valor_contrato en pesos colombianos (COP), tal como lo
--                       reporta la entidad. No se ajusta por inflación.
--   * Departamento    : el de la ENTIDAD que contrata, no el de ejecución del
--                       contrato (el dataset no trae el segundo de forma fiable).
--   * Duración        : fecha de fin menos fecha de inicio, en días, solo si las
--                       fechas son coherentes (ver f_fechas_imposibles).
--   * Grupo de modalidad: Contratación directa / Régimen especial / Competitiva /
--                       Otra, a partir de la modalidad que escribe la entidad.
--
-- Valor inválido:
--   * cero;
--   * menor que $ 1.000 (menos de un cuarto de dólar): no es un contrato real,
--     es una cifra en miles mal digitada o una prueba;
--   * de 1 billón de pesos (1e12) o más: son 3 contratos, de una institución
--     educativa, una personería y una dirección seccional de administración
--     judicial, con valores de hasta 6.453 billones, más de diez veces el
--     presupuesto de la nación. Son ceros de más al digitar. El siguiente contrato más grande
--     (0,97 billones) sí es plausible. Ver 08_calidad_hallazgos.sql.
-- =====================================================================
\set ON_ERROR_STOP on

SET client_min_messages = warning;  -- silencia los avisos de DROP ... IF EXISTS

DROP MATERIALIZED VIEW IF EXISTS mart.fact_contrato CASCADE;

-- ---------------------------------------------------------------------
-- mart.fact_contrato — grano: 1 fila por contrato (id_contrato).
-- Cada problema de calidad es una columna f_*: nada se borra, todo se marca.
-- ---------------------------------------------------------------------
CREATE MATERIALIZED VIEW mart.fact_contrato AS
SELECT c.id_contrato,
       c.entidad_id,
       c.proveedor_id,
       c.firmado_en,
       DATE_TRUNC('month', c.firmado_en)::DATE                  AS mes_firma,
       c.modalidad,
       CASE
           WHEN c.modalidad ILIKE 'Contratación directa%'            THEN 'Contratación directa'
           WHEN c.modalidad ILIKE 'Contratación régimen especial%'   THEN 'Régimen especial'
           WHEN c.modalidad ILIKE 'Licitación%'
             OR c.modalidad ILIKE 'Selecci%'
             OR c.modalidad ILIKE 'Concurso de méritos%'
             OR c.modalidad ILIKE 'Mínima cuantía%'
             OR c.modalidad ILIKE 'Subasta%'                          THEN 'Competitiva'
           ELSE 'Otra'
       END                                                       AS modalidad_grupo,
       c.tipo_contrato,
       c.estado,
       c.valor_contrato,
       c.valor_pagado,
       c.valor_facturado,
       c.dias_adicionados,
       c.inicio_en,
       c.fin_en,
       -- duración solo con fechas coherentes
       CASE WHEN c.inicio_en IS NOT NULL AND c.fin_en IS NOT NULL
             AND c.fin_en >= c.inicio_en
             AND EXTRACT(YEAR FROM c.inicio_en) BETWEEN 2000 AND 2100
             AND EXTRACT(YEAR FROM c.fin_en)    BETWEEN 2000 AND 2100
            THEN c.fin_en::DATE - c.inicio_en::DATE END         AS duracion_dias,
       CASE WHEN pr.tipo_documento = 'NIT'                       THEN 'Persona jurídica'
            WHEN pr.tipo_documento ILIKE 'Cédula%'
              OR pr.tipo_documento ILIKE 'Permiso%'
              OR pr.tipo_documento ILIKE 'Pasaporte%'            THEN 'Persona natural'
            WHEN pr.proveedor_id IS NULL                         THEN 'Sin proveedor'
            ELSE 'Otro documento' END                            AS proveedor_tipo,
       -- --- marcas de calidad ---------------------------------------
       (c.valor_contrato = 0)                                    AS f_valor_cero,
       (c.valor_contrato >= 1e12)                                AS f_valor_absurdo,
       (c.valor_contrato > 0 AND c.valor_contrato < 1000)        AS f_valor_minusculo,
       (c.inicio_en IS NULL OR c.fin_en IS NULL)                 AS f_sin_fechas,
       (c.inicio_en IS NOT NULL AND c.fin_en IS NOT NULL AND
          (c.fin_en < c.inicio_en
           OR EXTRACT(YEAR FROM c.inicio_en) NOT BETWEEN 2000 AND 2100
           OR EXTRACT(YEAR FROM c.fin_en)    NOT BETWEEN 2000 AND 2100
           OR c.fin_en::DATE < c.firmado_en::DATE))              AS f_fechas_imposibles,
       (e.nit !~ '^[0-9]{5,10}$' OR e.nit ~ '^(.)\1+$')          AS f_nit_entidad_invalido,
       (pr.proveedor_id IS NOT NULL AND pr.tipo_documento IN ('NIT') AND
          (pr.documento !~ '^[0-9]{5,11}$' OR pr.documento ~ '^(.)\1+$')) AS f_nit_proveedor_invalido,
       (pr.proveedor_id IS NOT NULL AND pr.tipo_documento ILIKE 'Cédula%' AND
          (pr.documento !~ '^[0-9]{5,11}$' OR pr.documento ~ '^(.)\1+$')) AS f_cedula_invalida,
       (pr.proveedor_id IS NULL)                                 AS f_sin_proveedor,
       (c.valor_pagado > c.valor_contrato AND c.valor_contrato > 0) AS f_pagado_excede,
       (c.rn_repetido > 1)                                       AS f_posible_repetido,
       (c.valor_contrato >= 1000 AND c.valor_contrato < 1e12 AND c.rn_repetido = 1) AS is_valid
FROM (SELECT k.*,
             CASE WHEN k.referencia IS NOT NULL AND k.proveedor_id IS NOT NULL AND k.valor_contrato >= 1000
                  THEN ROW_NUMBER() OVER (PARTITION BY k.entidad_id, k.proveedor_id, k.valor_contrato,
                                                       k.referencia, k.firmado_en::DATE
                                          ORDER BY k.id_contrato)
                  ELSE 1 END AS rn_repetido
      FROM core.contrato AS k) AS c
JOIN core.entidad  AS e  ON e.entidad_id = c.entidad_id
LEFT JOIN core.proveedor AS pr ON pr.proveedor_id = c.proveedor_id;

CREATE UNIQUE INDEX ON mart.fact_contrato (id_contrato);
CREATE INDEX ON mart.fact_contrato (entidad_id);
CREATE INDEX ON mart.fact_contrato (proveedor_id);
CREATE INDEX ON mart.fact_contrato (mes_firma);
ANALYZE mart.fact_contrato;
