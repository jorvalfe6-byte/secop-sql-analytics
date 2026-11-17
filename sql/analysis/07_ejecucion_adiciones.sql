-- =====================================================================
-- 07_ejecucion_adiciones.sql — Valor pagado vs. contratado y contratos modificados.
-- Consulta 1: 1 fila por estado del contrato.
-- Consulta 2: una fila de resumen.
-- El dataset NO trae el valor de las adiciones en dinero: solo dias_adicionados
-- y el estado 'Modificado'. El valor pagado es una foto del momento de la descarga.
-- =====================================================================
SELECT COALESCE(estado, 'Sin estado')                                           AS estado,
       COUNT(*)                                                                 AS contratos,
       SUM(valor_contrato)                                                      AS valor_contratado,
       SUM(LEAST(COALESCE(valor_pagado, 0), valor_contrato))                    AS valor_pagado,
       ROUND(100.0 * SUM(LEAST(COALESCE(valor_pagado, 0), valor_contrato))
                   / SUM(valor_contrato), 1)                                    AS pct_pagado,
       COUNT(*) FILTER (WHERE dias_adicionados > 0)                             AS con_dias_adicionados
FROM mart.fact_contrato
WHERE is_valid
GROUP BY estado ORDER BY valor_contratado DESC;

SELECT COUNT(*) FILTER (WHERE dias_adicionados > 0)                             AS con_dias_adicionados,
       ROUND(AVG(dias_adicionados) FILTER (WHERE dias_adicionados > 0), 0)      AS dias_adicionados_promedio,
       MAX(dias_adicionados)                                                    AS dias_adicionados_max,
       COUNT(*) FILTER (WHERE f_pagado_excede)                                  AS pagado_mayor_que_contratado,
       COUNT(*) FILTER (WHERE valor_pagado IS NULL OR valor_pagado = 0)         AS sin_pagos_registrados
FROM mart.fact_contrato
WHERE is_valid;
