-- =====================================================================
-- 06_duracion.sql — Duración de los contratos (fin menos inicio, en días).
-- Consulta 1: 1 fila por tramo de duración.
-- Consulta 2: 1 fila por grupo de modalidad, con percentiles.
-- Solo contratos válidos con fechas coherentes (duracion_dias no nulo).
-- Técnicas: CASE para tramos, percentiles, participación con ventana.
-- =====================================================================
SELECT CASE WHEN duracion_dias <= 30  THEN '1) hasta 1 mes'   WHEN duracion_dias <= 90  THEN '2) 1 a 3 meses'
            WHEN duracion_dias <= 180 THEN '3) 3 a 6 meses'   WHEN duracion_dias <= 365 THEN '4) 6 a 12 meses'
            WHEN duracion_dias <= 730 THEN '5) 1 a 2 años'    ELSE '6) más de 2 años' END AS tramo,
       COUNT(*)                                                     AS contratos,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)           AS pct_contratos,
       ROUND(100.0 * SUM(valor_contrato) / SUM(SUM(valor_contrato)) OVER (), 1) AS pct_valor
FROM mart.fact_contrato
WHERE is_valid AND duracion_dias IS NOT NULL
GROUP BY 1 ORDER BY 1;

SELECT modalidad_grupo,
       COUNT(*)                                                    AS contratos,
       PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duracion_dias) AS p25_dias,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duracion_dias) AS mediana_dias,
       PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duracion_dias) AS p75_dias,
       PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY duracion_dias) AS p90_dias
FROM mart.fact_contrato
WHERE is_valid AND duracion_dias IS NOT NULL
GROUP BY modalidad_grupo ORDER BY contratos DESC;
