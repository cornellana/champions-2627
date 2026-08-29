#!/bin/sh
# Pone al día el clon del repositorio y arranca el demonio.
#
# El demonio vive DENTRO del repositorio (nas/champions_daemon.py), así que
# actualizarlo es un `git push` desde el Mac y un reinicio del contenedor. No
# hay copias sueltas de código dando vueltas por el NAS.
set -e

REPO="${CHAMPIONS_REPO:-/repo}"
URL="${CHAMPIONS_REPO_URL:-https://github.com/cornellana/champions-2627.git}"
CLAVE="${CHAMPIONS_DEPLOY_KEY:-/estado/ssh/id_ed25519}"

# La clave se prepara ANTES de tocar el clon, no después: el clon recuerda el
# remoto por SSH de arranques anteriores, así que sin GIT_SSH_COMMAND el fetch
# de más abajo muere con «Host key verification failed» y el contenedor
# arrancaría con el código de la vez pasada.
if [ -f "$CLAVE" ]; then
    chmod 600 "$CLAVE" 2>/dev/null || true
    export GIT_SSH_COMMAND="ssh -i $CLAVE -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/estado/ssh/known_hosts"
fi

# También antes de tocar el clon: el volumen viene del host y es de otro dueño,
# así que git se niega a operar en él («dubious ownership») y el fetch falla en
# silencio.
git config --global --add safe.directory "$REPO" 2>/dev/null || true

if [ -d "$REPO/.git" ]; then
    echo "Actualizando el clon en $REPO…"
    git -C "$REPO" fetch -q origin main \
        || echo "  (no se pudo contactar con el remoto: sigo con lo que hay clonado)"
    git -C "$REPO" checkout -q -B main origin/main || true
else
    echo "Clonando $URL en $REPO…"
    git clone -q "$URL" "$REPO"
fi

# Quién firma los commits del NAS. Se distingue a simple vista de los de
# github-actions[bot]: ver uno del bot en el historial significa que el NAS
# estuvo caído.
git -C "$REPO" config user.name  "champions-nas[bot]"
git -C "$REPO" config user.email "champions-nas@cornellanas.net"

# Con deploy key se empuja por SSH. Sin ella el clon es de solo lectura por
# HTTPS, que es lo que necesita el modo sombra. El remoto se fija aquí y no
# arriba porque el clon en frío se hace por HTTPS.
if [ -f "$CLAVE" ]; then
    git -C "$REPO" remote set-url origin "git@github.com:cornellana/champions-2627.git"
    echo "Deploy key encontrada: remoto por SSH (puede publicar)."
else
    echo "Sin deploy key: remoto de solo lectura (modo sombra)."
fi

echo "Versión del repositorio: $(git -C "$REPO" log -1 --format='%h %s' 2>/dev/null || echo desconocida)"
exec python3 "$REPO/nas/champions_daemon.py"
