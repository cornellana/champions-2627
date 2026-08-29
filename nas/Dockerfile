# El NAS trae Python 3.12 pero sin pip, sin requests y sin git. En vez de
# ensuciar el sistema del QNAP instalando cosas a mano, el actualizador vive en
# su propio contenedor, al lado de los de La Liga y sin tocarlos.
FROM python:3.12-slim

# git: para clonar el repositorio y, en producción, publicar el JSON.
# ca-certificates y openssh-client: para hablar con ESPN y con GitHub.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates openssh-client \
 && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir requests

# El updater trabaja en UTC pero convierte a hora de Madrid, así que necesita
# la base de datos de zonas horarias.
ENV TZ=Europe/Madrid
ENV PYTHONUNBUFFERED=1

WORKDIR /estado
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# El demonio deja una marca de vida en cada ciclo. Si deja de latir media hora,
# el contenedor se marca como unhealthy y se ve en `docker ps` sin entrar a
# mirar el log.
#
# timegm y no mktime: la marca está en UTC y mktime la interpretaría como hora
# local. Con el contenedor en CEST le sumaba dos horas de antigüedad fantasma y
# se declaraba enfermo siempre, aunque acabara de latir. Es un fallo que ya se
# pagó en el contenedor de La Liga; aquí viene corregido de fábrica.
HEALTHCHECK --interval=5m --timeout=10s --start-period=2m \
  CMD python3 -c "import json,time,calendar,sys; s=json.load(open('/estado/salud.json')); \
      t=calendar.timegm(time.strptime(s['actualizado'],'%Y-%m-%dT%H:%M:%SZ')); \
      sys.exit(0 if (time.time()-t) < 1800 else 1)" || exit 1

ENTRYPOINT ["/entrypoint.sh"]
