-- =====================================================================
-- 03_departamentos_sectores.sql — Valor por departamento y por sector.
-- Grano: 1 fila por departamento (primera consulta) y 1 por sector (segunda).
-- Ojo: el departamento es el de la entidad que contrata, no el de ejecución.
-- Técnicas: ventana para participación, ranking y acumulado; PERCENTILE_CONT.
-- =====================================================================
SELECT RANK() OVER (ORDER BY SUM(f.valor_contrato) DESC)                         AS ranking,
       e.departamento,
       COUNT(*)                                                                  AS contratos,
       SUM(f.valor_contrato)                                                     AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) / SUM(SUM(f.valor_contrato)) OVER (), 2) AS pct_valor,
       ROUND(100.0 * SUM(SUM(f.valor_contrato)) OVER (ORDER BY SUM(f.valor_contrato) DESC)
                   / SUM(SUM(f.valor_contrato)) OVER (), 1)                      AS pct_acumulado,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.valor_contrato)::NUMERIC, 0) AS valor_mediano
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
WHERE f.is_valid
GROUP BY e.departamento
ORDER BY valor DESC;

SELECT RANK() OVER (ORDER BY SUM(f.valor_contrato) DESC)                         AS ranking,
       e.sector,
       COUNT(*)                                                                  AS contratos,
       COUNT(DISTINCT f.entidad_id)                                              AS entidades,
       SUM(f.valor_contrato)                                                     AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) / SUM(SUM(f.valor_contrato)) OVER (), 2) AS pct_valor
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
WHERE f.is_valid
GROUP BY e.sector
ORDER BY valor DESC;
