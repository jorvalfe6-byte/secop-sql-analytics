-- =====================================================================
-- 08_calidad_hallazgos.sql — Qué tan limpia viene la fuente.
-- Consulta 1: cuántos contratos tienen cada problema (los mismos números que
--             el dashboard). Un contrato puede tener varios.
-- Consulta 2: los 10 valores más altos (para justificar el tope de "absurdo").
-- Consulta 3: distribución de valores por rango, para ver cuántos son de cero o minúsculos.
-- Consulta 4: cuántas veces aparece cada tipo de documento del proveedor.
-- Estos hallazgos NO son errores de carga: la carga reproduce lo que dice la fuente.
-- =====================================================================
SELECT orden, problema, contratos, pct, criterio
FROM mart.dash_calidad
ORDER BY orden;

SELECT f.id_contrato, e.nombre AS entidad, f.valor_contrato, f.modalidad, f.is_valid
FROM mart.fact_contrato AS f JOIN core.entidad AS e USING (entidad_id)
ORDER BY f.valor_contrato DESC
LIMIT 10;

SELECT CASE WHEN valor_contrato = 0              THEN '1) cero'
            WHEN valor_contrato < 1000           THEN '2) menos de $ 1.000'
            WHEN valor_contrato < 1000000        THEN '3) $ 1.000 a 1 millón'
            WHEN valor_contrato < 100000000      THEN '4) 1 a 100 millones'
            WHEN valor_contrato < 10000000000    THEN '5) 100 millones a 10 mil millones'
            WHEN valor_contrato < 1000000000000  THEN '6) 10 mil millones a 1 billón'
            ELSE                                      '7) 1 billón o más' END AS rango,
       COUNT(*)                                                     AS contratos,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)           AS pct_contratos
FROM mart.fact_contrato
GROUP BY 1 ORDER BY 1;

SELECT tipo_documento, COUNT(*) AS proveedores
FROM core.proveedor
GROUP BY tipo_documento ORDER BY proveedores DESC;
