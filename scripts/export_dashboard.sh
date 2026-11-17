#!/usr/bin/env bash
# Exporta las vistas mart.dash_* a un único JSON que lee el dashboard.
# Solo salen agregados aquí; el único detalle individual son los 15 mayores
# proveedores que son personas jurídicas (NIT). Ninguna persona natural aparece.
set -euo pipefail

# los textos del dataset llevan tildes: que psql en Windows no use la página de códigos de la consola
export PGCLIENTENCODING=UTF8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/data/dashboard.json"
mkdir -p "$(dirname "$OUT")"

psql -X -q -At -v ON_ERROR_STOP=1 > "$OUT" <<'SQL'
SELECT json_build_object(
    -- fecha de la carga, no de la exportación: exportar dos veces da el mismo archivo
    'generado',      (SELECT to_char(MAX(loaded_at), 'YYYY-MM-DD') FROM audit.load_log),
    'kpis',          (SELECT row_to_json(k) FROM mart.dash_kpis k),
    'mensual',       (SELECT json_agg(m ORDER BY mes)               FROM mart.dash_mensual m),
    'departamentos', (SELECT json_agg(d ORDER BY valor DESC)        FROM mart.dash_departamentos d),
    'sectores',      (SELECT json_agg(s ORDER BY valor DESC)        FROM mart.dash_sectores s),
    'entidades',     (SELECT json_agg(e ORDER BY ranking)           FROM mart.dash_top_entidades e),
    'proveedores',   (SELECT json_agg(p ORDER BY ranking)           FROM mart.dash_top_proveedores p),
    'concentracion', (SELECT json_agg(c ORDER BY orden)             FROM mart.dash_concentracion c),
    'modalidades',   (SELECT json_agg(m ORDER BY valor DESC)        FROM mart.dash_modalidades m),
    'grupos_modalidad', (SELECT json_agg(g ORDER BY orden)          FROM mart.dash_grupos_modalidad g),
    'duracion',      (SELECT json_agg(d ORDER BY orden)             FROM mart.dash_duracion d),
    'ejecucion',     (SELECT row_to_json(e) FROM mart.dash_ejecucion e),
    'calidad',       (SELECT json_agg(c ORDER BY orden)             FROM mart.dash_calidad c)
);
SQL

echo "→ $OUT ($(wc -c < "$OUT") bytes)"
