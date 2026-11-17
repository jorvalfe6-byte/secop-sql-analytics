#!/usr/bin/env bash
# Carga completa: esquema → staging → core → marts → dashboard → Power BI → validación.
# Uso:
#   export PGHOST=localhost PGUSER=postgres PGDATABASE=secop
#   ./scripts/load.sh            # usa ./data por defecto
#   ./scripts/load.sh /ruta/csv
set -euo pipefail

# los textos del dataset llevan tildes: que psql en Windows no use la página de códigos de la consola
export PGCLIENTENCODING=UTF8

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${1:-$ROOT/data}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

# psql.exe en Windows no entiende rutas estilo /c/Users/...; en Linux/macOS no hace falta
ruta() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi; }

shopt -s nullglob
files=("$DATA_DIR"/secop_contratos_*.csv)
if (( ${#files[@]} == 0 )); then
    echo "No hay archivos secop_contratos_*.csv en $DATA_DIR" >&2
    echo "Corre primero ./scripts/download_data.sh" >&2
    exit 1
fi
if [[ ! -f "$DATA_DIR/_conteo_api.csv" ]]; then
    echo "Falta $DATA_DIR/_conteo_api.csv (lo escribe download_data.sh)" >&2
    exit 1
fi

echo "→ esquema";  "${PSQL[@]}" -f "$ROOT/sql/01_schema.sql"
echo "→ tablas core"; "${PSQL[@]}" -f "$ROOT/sql/02_core_tables.sql"
echo "→ staging (${#files[@]} archivos)"
for f in "${files[@]}"; do
    echo "   $(basename "$f")"
    "${PSQL[@]}" -c "\copy staging.contratos FROM '$(ruta "$f")' WITH (FORMAT csv, HEADER true)"
done
"${PSQL[@]}" -c "\copy staging.conteo_api FROM '$(ruta "$DATA_DIR/_conteo_api.csv")' WITH (FORMAT csv, HEADER true)"
echo "→ transformación"; "${PSQL[@]}" -f "$ROOT/sql/03_transform.sql"
echo "→ marts";     "${PSQL[@]}" -f "$ROOT/sql/04_marts.sql"
echo "→ dashboard"; "${PSQL[@]}" -f "$ROOT/sql/05_dashboard_views.sql"
echo "→ power bi";  "${PSQL[@]}" -f "$ROOT/sql/06_powerbi_views.sql"
echo "→ power bi (extracto)"; "${PSQL[@]}" -f "$ROOT/sql/07_powerbi_extract.sql"
echo "→ validación"
controles="$("${PSQL[@]}" -f "$ROOT/sql/analysis/00_calidad_datos.sql")"
echo "$controles"
if grep -q 'REVISAR' <<<"$controles"; then
    echo "Hay controles de calidad en REVISAR: la carga no coincide con lo esperado." >&2
    exit 1
fi
echo "Listo."
