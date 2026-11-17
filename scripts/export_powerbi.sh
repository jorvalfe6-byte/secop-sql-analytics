#!/usr/bin/env bash
# Exporta cada vista del esquema powerbi_extract (agregado, ver
# sql/07_powerbi_extract.sql) a powerbi/data/<vista>.csv.
# El informe de Power BI lee esos CSV, así que se abre sin PostgreSQL.
# Uso:
#   export PGHOST=localhost PGUSER=postgres PGDATABASE=secop
#   ./scripts/export_powerbi.sh
set -euo pipefail
export PGCLIENTENCODING=UTF8   # psql de Windows usa la página de códigos de la consola

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/powerbi/data"
mkdir -p "$OUT"
# psql de Windows no entiende rutas /c/...: se convierten si existe cygpath
OUT_PSQL="$OUT"; command -v cygpath >/dev/null && OUT_PSQL="$(cygpath -m "$OUT")"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

views="$("${PSQL[@]}" -At -c "SELECT table_name FROM information_schema.views WHERE table_schema = 'powerbi_extract' ORDER BY 1")"
[[ -n "$views" ]] || { echo "No hay vistas en el esquema powerbi_extract: corre la carga primero." >&2; exit 1; }
for v in $views; do
    v="${v%$'\r'}"   # psql de Windows termina las líneas en CRLF
    echo "→ $v.csv"
    "${PSQL[@]}" -c "\copy (SELECT * FROM powerbi_extract.$v ORDER BY 1) TO '$OUT_PSQL/$v.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')"
done
echo "Listo: CSV en $OUT"
