-- =====================================================================
-- 02_valor_mensual.sql — Valor contratado por mes de firma.
-- Grano: 1 fila por mes (calendario continuo con generate_series).
-- Técnicas: LAG para variación mes a mes, media móvil de 3 meses,
-- acumulado del año, participación de cada mes con SUM() OVER ().
-- =====================================================================
WITH calendario AS (
    SELECT generate_series(MIN(mes_firma), MAX(mes_firma), INTERVAL '1 month')::DATE AS mes
    FROM mart.fact_contrato
),
mensual AS (
    SELECT mes_firma AS mes, COUNT(*) AS contratos, SUM(valor_contrato) AS valor
    FROM mart.fact_contrato WHERE is_valid GROUP BY mes_firma
)
SELECT c.mes,
       COALESCE(m.contratos, 0)                                               AS contratos,
       COALESCE(m.valor, 0)                                                   AS valor,
       ROUND(100.0 * (m.valor - LAG(m.valor) OVER (ORDER BY c.mes))
                   / NULLIF(LAG(m.valor) OVER (ORDER BY c.mes), 0), 1)        AS var_mensual_pct,
       ROUND(AVG(COALESCE(m.valor, 0)) OVER (ORDER BY c.mes ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS media_movil_3m,
       SUM(COALESCE(m.valor, 0)) OVER (ORDER BY c.mes)                        AS acumulado,
       ROUND(100.0 * m.valor / SUM(m.valor) OVER (), 1)                       AS pct_del_anio
FROM calendario AS c LEFT JOIN mensual AS m USING (mes)
ORDER BY c.mes;
