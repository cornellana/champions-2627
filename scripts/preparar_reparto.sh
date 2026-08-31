#!/usr/bin/env bash
#
# preparar_reparto.sh — lo que hay que hacer justo antes de compilar Champions
# para repartirla.
#
# Lo llama solo `Reparto/repartir.sh`, que busca este fichero en cada proyecto
# y lo ejecuta si existe. Aquí va lo propio de esta app y nada más; el resto
# —firmar, publicar, verificar— es común y vive allí.

set -euo pipefail

cd "$(dirname "$0")/.."

echo "  · regenerando el icono"
swift scripts/render_icon.swift >/dev/null

# El calendario viaja dentro de la app como semilla, para que arranque con algo
# aunque no haya red. Si se reparte con el de hace un mes, el probador ve
# jornadas viejas hasta que la app termina de bajarse las de verdad.
echo "  · refrescando el calendario que viaja dentro de la app"
python3 scripts/fetch_season.py >/dev/null
cp data/champions2627.json Champions/champions2627-seed.json
