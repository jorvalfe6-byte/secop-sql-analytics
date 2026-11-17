-- =====================================================================
-- 05_modalidades.sql — Cómo se contrata: directa, régimen especial o competitiva.
-- Consulta 1: 1 fila por grupo de modalidad.
-- Consulta 2: 1 fila por modalidad original (como la escribe la entidad).
-- Consulta 3: 1 fila por sector, con el reparto del valor entre grupos.
-- Técnicas: participación con SUM() OVER (), PERCENTILE_CONT, pivot con FILTER.
-- =====================================================================
SELECT modalidad_grupo,
       COUNT(*)                                                         AS contratos,
       SUM(valor_contrato)                                              AS valor,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_contratos,
       ROUND(100.0 * SUM(valor_contrato) / SUM(SUM(valor_contrato)) OVER (), 1) AS pct_valor,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valor_contrato)::NUMERIC, 0) AS valor_mediano
FROM mart.fact_contrato WHERE is_valid
GROUP BY modalidad_grupo ORDER BY valor DESC;

SELECT COALESCE(modalidad, 'Sin modalidad') AS modalidad, modalidad_grupo,
       COUNT(*) AS contratos, SUM(valor_contrato) AS valor,
       ROUND(100.0 * SUM(valor_contrato) / SUM(SUM(valor_contrato)) OVER (), 2) AS pct_valor
FROM mart.fact_contrato WHERE is_valid
GROUP BY modalidad, modalidad_grupo ORDER BY valor DESC;

SELECT e.sector,
       SUM(f.valor_contrato)                                                              AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) FILTER (WHERE f.modalidad_grupo = 'Contratación directa') / SUM(f.valor_contrato), 1) AS pct_directa,
       ROUND(100.0 * SUM(f.valor_contrato) FILTER (WHERE f.modalidad_grupo = 'Régimen especial')     / SUM(f.valor_contrato), 1) AS pct_regimen_especial,
       ROUND(100.0 * SUM(f.valor_contrato) FILTER (WHERE f.modalidad_grupo = 'Competitiva')           / SUM(f.valor_contrato), 1) AS pct_competitiva
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
WHERE f.is_valid
GROUP BY e.sector HAVING SUM(f.valor_contrato) > 0
ORDER BY valor DESC;
