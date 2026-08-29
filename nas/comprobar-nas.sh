#!/usr/bin/env bash
#
# comprobar-nas.sh — mira cómo está todo. No toca nada.

set -uo pipefail
NAS="${NAS_HOST:-nas}"
ENTORNO='export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH;'
nas() { ssh "$NAS" "$ENTORNO $*"; }

echo "═══ Contenedores del fútbol ═══"
nas 'docker ps -a --filter name=laliga --filter name=champions --format "{{.Names}}\t{{.Status}}"'

echo
echo "═══ Memoria del NAS ═══"
nas 'free -m | head -2'

echo
echo "═══ Salud del actualizador de la Champions ═══"
nas 'cat /share/Container/champions-updater/estado/salud.json 2>/dev/null' \
    || echo "  (todavía no ha escrito ninguna marca)"

echo
echo "═══ Últimas líneas del log ═══"
nas 'docker logs --tail 15 champions-updater 2>&1' || echo "  (sin contenedor)"

echo
echo "═══ La Liga, que no se toca ═══"
printf "  health de laliga-api: "
curl -fsS --max-time 10 https://laliga-api.cornellanas.net/health || echo "SIN RESPUESTA"
echo
printf "  datos de La Liga:     "
curl -fsS -o /dev/null -w "%{http_code}\n" --max-time 10 \
    https://laliga-api.cornellanas.net/datos/laliga2627.json

echo
echo "═══ Datos publicados de la Champions ═══"
printf "  GitHub: "
curl -fsS --max-time 15 \
    https://raw.githubusercontent.com/cornellana/champions-2627/main/data/champions2627.json \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['lastUpdated'], '·', sum(len(x['games']) for x in d['matchDays']), 'partidos')" \
    2>/dev/null || echo "no disponible"
