#!/usr/bin/env bash
#
# instalar.sh — monta el actualizador de la Champions en el NAS.
#
# Es idempotente: se puede ejecutar las veces que haga falta.
#
# Lo primero y lo último que hace es comprobar que La Liga sigue en pie. Ese
# contenedor es el titular de una competición en marcha y lo de aquí no puede
# rozarlo: carpeta propia, volúmenes propios, imagen propia y clon propio. Si
# la comprobación previa falla, no se instala nada.
#
#   ./nas/instalar.sh                 instala o actualiza (modo sombra)
#   CHAMPIONS_MODO=produccion ./nas/instalar.sh   instala publicando

set -euo pipefail

NAS="${NAS_HOST:-nas}"
DESTINO="/share/Container/champions-updater"
MODO="${CHAMPIONS_MODO:-sombra}"
AQUI="$(cd "$(dirname "$0")" && pwd)"

# Container Station no está en el PATH del shell de QNAP.
ENTORNO='export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; export DOCKER_CONFIG=$HOME/.docker;'

nas() { ssh "$NAS" "$ENTORNO $*"; }

# ── Lo de La Liga, antes de tocar nada ──────────────────────────────────────

echo "▸ Comprobando que La Liga está bien ANTES de tocar nada"
ANTES=$(nas 'docker ps --filter name=laliga --format "{{.Names}}|{{.Status}}"' || true)
if [ -z "$ANTES" ]; then
    echo "✗ No veo los contenedores de La Liga. Me paro: algo raro pasa y no es"
    echo "  momento de instalar nada encima."
    exit 1
fi
echo "$ANTES" | sed 's/^/    /'

echo "▸ Instalando en $DESTINO (modo $MODO)"
nas "mkdir -p $DESTINO/estado $DESTINO/repo $DESTINO/publico"

# Solo los ficheros del contenedor. El código del demonio y del updater llega
# por el clon de git, no por scp: así no hay dos copias que puedan divergir.
scp -q -O "$AQUI/Dockerfile" "$AQUI/docker-compose.yml" "$AQUI/entrypoint.sh" \
    "$NAS:$DESTINO/"

nas "printf 'CHAMPIONS_MODO=%s\n' '$MODO' > $DESTINO/.env"

# ── Construir y arrancar ────────────────────────────────────────────────────
#
# DOCKER_BUILDKIT=0 a propósito: el BuildKit de Container Station falla al
# montar los datasets de las capas y ni siquiera llega a leer el Dockerfile.
# El constructor clásico usa el mismo almacenamiento y sí funciona.

echo "▸ Construyendo la imagen"
nas "cd $DESTINO && DOCKER_BUILDKIT=0 docker build -q -t champions-updater ."

echo "▸ Arrancando"
nas "cd $DESTINO && docker compose up -d --force-recreate"

# ── Y La Liga, después ──────────────────────────────────────────────────────

echo "▸ Comprobando que La Liga sigue igual DESPUÉS"
sleep 5
DESPUES=$(nas 'docker ps --filter name=laliga --format "{{.Names}}|{{.Status}}"' || true)
echo "$DESPUES" | sed 's/^/    /'

if [ "$(echo "$ANTES" | cut -d'|' -f1 | sort)" != "$(echo "$DESPUES" | cut -d'|' -f1 | sort)" ]; then
    echo "✗ Los contenedores de La Liga han cambiado. Revísalo YA."
    exit 1
fi

echo "▸ Y que su API sigue respondiendo"
curl -fsS --max-time 15 https://laliga-api.cornellanas.net/health \
    && echo "" \
    || { echo "✗ laliga-api no responde. Revísalo."; exit 1; }

echo
echo "✅ Instalado. Log en vivo:"
echo "   ssh $NAS '$ENTORNO docker logs -f champions-updater'"
