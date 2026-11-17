#!/usr/bin/env bash
# Baja de datos.gov.co (API SODA, sin cuenta) los contratos de SECOP II firmados
# en un año (por defecto 2024), un CSV por mes de firma. Solo usa Python 3 con la
# biblioteca estándar. Dataset: jbjy-vk9h (SECOP II - Contratos Electrónicos).
#
# - Pide solo las columnas necesarias. Deja fuera a propósito los datos de personas
#   que el análisis no necesita (representantes legales, supervisores, ordenadores
#   del gasto, cuentas bancarias, direcciones).
# - Orden estable (id_contrato, id interno de Socrata) y páginas de 20.000 filas.
# - Cada mes se baja a un archivo temporal y solo se renombra si el número de filas
#   coincide con el conteo que da la API. Si el archivo ya está completo, lo salta,
#   así que se puede volver a correr tras un corte de red.
# - Escribe data/_conteo_api.csv (mes, filas): load.sh lo usa como control.
#
# Uso: ./scripts/download_data.sh [año] [carpeta_destino]   (por defecto 2024 y ./data)
# Variable opcional: SECOP_MUESTRA=N baja solo las primeras N filas de cada mes
# (es lo que usa el CI; ver README).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YEAR="${1:-2024}"
DEST="${2:-$ROOT/data}"
mkdir -p "$DEST"

# python3 en Linux/macOS; en Windows a veces solo existe "python"
PY=python3
"$PY" -c "" 2>/dev/null || PY=python

bajar_mes() {
    local m="$1"
    "$PY" -I - "$YEAR" "$m" "$DEST" "${SECOP_MUESTRA:-0}" <<'PY'
import calendar, csv, http.client, io, os, sys, time, urllib.parse, urllib.request

year, month, dest, muestra = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
BASE = "https://www.datos.gov.co/resource/jbjy-vk9h.csv"
COLS = """nombre_entidad nit_entidad codigo_entidad departamento ciudad orden sector rama
entidad_centralizada proceso_de_compra id_contrato referencia_del_contrato estado_contrato
codigo_de_categoria_principal tipo_de_contrato modalidad_de_contratacion justificacion_modalidad_de
fecha_de_firma fecha_de_inicio_del_contrato fecha_de_fin_del_contrato duraci_n_del_contrato
tipodocproveedor documento_proveedor codigo_proveedor proveedor_adjudicado es_grupo es_pyme
habilita_pago_adelantado liquidaci_n el_contrato_puede_ser_prorrogado origen_de_los_recursos
destino_gasto valor_del_contrato valor_de_pago_adelantado valor_facturado valor_pendiente_de_pago
valor_pagado dias_adicionados ultima_actualizacion""".split()
last = calendar.monthrange(year, month)[1]
where = (f"fecha_de_firma between '{year}-{month:02d}-01T00:00:00' "
         f"and '{year}-{month:02d}-{last}T23:59:59'")
tag = f"{year}{month:02d}"
final = os.path.join(dest, f"secop_contratos_{tag}.csv")
conteo = os.path.join(dest, f".conteo_{tag}")
PAGE = 20000

def pedir(params):
    q = urllib.parse.urlencode(params)
    for intento in range(1, 7):
        try:
            with urllib.request.urlopen(f"{BASE}?{q}", timeout=300) as r:
                return r.read().decode("utf-8")
        except (OSError, http.client.HTTPException) as e:   # IncompleteRead no es OSError
            if intento == 6:
                sys.exit(f"{tag}: falló la descarga: {e}")
            time.sleep(4 * intento)

def filas_archivo(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return sum(1 for _ in csv.reader(fh)) - 1

total_api = int(list(csv.reader(io.StringIO(pedir({"$select": "count(*)", "$where": where}))))[1][0])
objetivo = min(muestra, total_api) if muestra else total_api

if os.path.exists(final) and filas_archivo(final) == objetivo:
    print(f"{tag}: ya estaba completo ({objetivo} filas)")
else:
    tmp = final + ".tmp"
    offset, rows, header = 0, 0, None
    with open(tmp, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        while rows < objetivo:
            limit = min(PAGE, objetivo - rows)
            texto = pedir({"$select": ",".join(COLS), "$where": where,
                           "$order": "id_contrato,:id", "$limit": limit, "$offset": offset})
            filas = list(csv.reader(io.StringIO(texto, newline="")))
            if not filas:
                break
            if header is None:
                header = filas[0]
                w.writerow(header)
            datos = filas[1:]
            w.writerows(datos)
            rows += len(datos)
            offset += len(datos)
            if len(datos) < limit:
                break
    if rows != objetivo:
        sys.exit(f"{tag}: se esperaban {objetivo} filas y llegaron {rows}; vuelve a correr el script")
    os.replace(tmp, final)
    print(f"{tag}: {rows} filas")

with open(conteo, "w", newline="\n") as fh:
    fh.write(f"{tag},{objetivo}\n")
PY
}

# 4 meses en paralelo: el servidor responde lento con tantas columnas
for m in 01 02 03 04 05 06 07 08 09 10 11 12; do
    while (( $(jobs -rp | wc -l) >= 4 )); do sleep 2; done
    bajar_mes "$m" &
done
fallos=0
for pid in $(jobs -rp); do wait "$pid" || fallos=1; done
(( fallos == 0 )) || { echo "Algún mes falló; vuelve a correr el script (retoma donde quedó)." >&2; exit 1; }

# conteo por mes: lo que debe coincidir con lo que se carga en staging
{ echo "mes,filas_api"; cat "$DEST"/.conteo_${YEAR}*; } > "$DEST/_conteo_api.csv"
echo "Listo: CSV en $DEST"
