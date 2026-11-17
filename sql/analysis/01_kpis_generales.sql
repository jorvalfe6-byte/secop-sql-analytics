-- =====================================================================
-- 01_kpis_generales.sql — Resumen ejecutivo.
-- Grano: una sola fila.
-- Solo contratos válidos (valor > 0 y no absurdo), salvo contratos_total.
-- =====================================================================
SELECT (SELECT COUNT(*) FROM mart.fact_contrato)                          AS contratos_total,
       COUNT(*)                                                           AS contratos_validos,
       SUM(valor_contrato)                                                AS valor_total_cop,
       ROUND(AVG(valor_contrato), 0)                                      AS valor_promedio,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valor_contrato)::NUMERIC, 0) AS valor_mediano,
       COUNT(DISTINCT entidad_id)                                         AS entidades,
       COUNT(DISTINCT proveedor_id)                                       AS proveedores,
       COUNT(*) FILTER (WHERE proveedor_tipo = 'Persona natural')         AS contratos_persona_natural,
       ROUND(100.0 * COUNT(*) FILTER (WHERE proveedor_tipo = 'Persona natural') / COUNT(*), 1) AS pct_persona_natural,
       ROUND(100.0 * SUM(valor_contrato) FILTER (WHERE proveedor_tipo = 'Persona natural')
                   / SUM(valor_contrato), 1)                              AS pct_valor_persona_natural,
       MIN(firmado_en)::DATE                                              AS primera_firma,
       MAX(firmado_en)::DATE                                              AS ultima_firma
FROM mart.fact_contrato
WHERE is_valid;
