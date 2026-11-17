-- =====================================================================
-- 04_concentracion_pareto.sql — Concentración del dinero en proveedores y entidades.
-- Consulta 1: resumen por actor (proveedores y entidades): cuánto del valor se
--             llevan el top 1 %, 10 %, 20 % y 50 %.
-- Consulta 2: las 10 entidades con más valor, con su dependencia de la contratación directa.
-- Consulta 3: los 10 proveedores con más valor (solo personas jurídicas).
-- Técnicas: SUM() OVER ordenado (acumulado), ROW_NUMBER, FILTER, UNION ALL.
-- =====================================================================
WITH por_actor AS (
    SELECT 'proveedor' AS actor, proveedor_id AS id, SUM(valor_contrato) AS valor
    FROM mart.fact_contrato WHERE is_valid AND proveedor_id IS NOT NULL GROUP BY proveedor_id
    UNION ALL
    SELECT 'entidad', entidad_id::TEXT, SUM(valor_contrato)
    FROM mart.fact_contrato WHERE is_valid GROUP BY entidad_id
),
curva AS (
    SELECT actor, id, valor,
           ROW_NUMBER() OVER (PARTITION BY actor ORDER BY valor DESC, id)     AS pos,
           COUNT(*) OVER (PARTITION BY actor)                                 AS n,
           SUM(valor) OVER (PARTITION BY actor ORDER BY valor DESC, id)
               / SUM(valor) OVER (PARTITION BY actor)                         AS acum
    FROM por_actor
)
SELECT actor,
       MAX(n)                                                         AS actores,
       ROUND(100 * MAX(acum) FILTER (WHERE pos <= CEIL(n * 0.01)), 1) AS pct_valor_top_1,
       ROUND(100 * MAX(acum) FILTER (WHERE pos <= CEIL(n * 0.10)), 1) AS pct_valor_top_10,
       ROUND(100 * MAX(acum) FILTER (WHERE pos <= CEIL(n * 0.20)), 1) AS pct_valor_top_20,
       ROUND(100 * MAX(acum) FILTER (WHERE pos <= CEIL(n * 0.50)), 1) AS pct_valor_top_50,
       MIN(pos) FILTER (WHERE acum >= 0.5)                            AS actores_para_el_50_pct
FROM curva
GROUP BY actor;

SELECT ROW_NUMBER() OVER (ORDER BY SUM(f.valor_contrato) DESC) AS ranking,
       e.nombre AS entidad, e.sector, e.departamento,
       COUNT(*)                                          AS contratos,
       SUM(f.valor_contrato)                             AS valor,
       ROUND(100.0 * SUM(f.valor_contrato) FILTER (WHERE f.modalidad_grupo = 'Contratación directa')
                   / SUM(f.valor_contrato), 1)           AS pct_directa
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
WHERE f.is_valid
GROUP BY e.entidad_id, e.nombre, e.sector, e.departamento
ORDER BY valor DESC LIMIT 10;

SELECT ROW_NUMBER() OVER (ORDER BY SUM(f.valor_contrato) DESC) AS ranking,
       p.nombre AS proveedor,
       COUNT(*)                                          AS contratos,
       COUNT(DISTINCT f.entidad_id)                      AS entidades,
       SUM(f.valor_contrato)                             AS valor
FROM mart.fact_contrato AS f JOIN core.proveedor AS p USING (proveedor_id)
WHERE f.is_valid AND f.proveedor_tipo = 'Persona jurídica'
GROUP BY p.proveedor_id, p.nombre
ORDER BY valor DESC LIMIT 10;
