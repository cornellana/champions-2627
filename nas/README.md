# El actualizador de la Champions en el NAS

Desde el **29/08/26 el NAS es el titular**: actualiza cada 60 segundos durante
los partidos y publica él en GitHub. El workflow de GitHub Actions está ahí,
pero como suplente: solo actúa si el NAS se calla más de veinte minutos.

Es el mismo reparto que en La Liga y por las mismas razones —el cron de GitHub
dispara cuando quiere, se han medido retrasos de hasta 39 minutos, y dos
ejecuciones cruzadas pueden dejar marcadores de conflicto dentro del JSON—.

## Lo primero: esto no toca La Liga

`laliga-updater` y `laliga-api` son el titular de una competición en marcha.
Lo de aquí vive completamente aparte:

| | La Liga | Champions |
|---|---|---|
| Contenedor | `laliga-updater` | `champions-updater` |
| Carpeta | `/share/Container/laliga-updater` | `/share/Container/champions-updater` |
| Imagen | `laliga-updater-laliga-updater` | `champions-updater` |
| Repositorio | `laliga-app-2627` | `champions-2627` |
| Clave de despliegue | la suya | la suya |
| Firma los commits | `laliga-nas[bot]` | `champions-nas[bot]` |

No comparten volumen, ni red, ni imagen, ni clon. Si esto se rompe, La Liga no
se entera.

**El demonio es una copia del de La Liga y no un módulo compartido, a
propósito.** Convertir en librería un proceso que lleva publicando desde el
22/08/26, a mitad de temporada, para ahorrarse trescientas líneas, es cambiar
riesgo real por elegancia.

`instalar.sh` comprueba los contenedores de La Liga y su API **antes** de tocar
nada —si no ve los contenedores, se para— y los vuelve a comprobar después,
comparando con la foto del antes.

## Qué gasta

Medido el 29/08/26, con el NAS a 13,2 GB de 15,7 usados:

```
laliga-updater      30,7 MB
laliga-api          27,9 MB
champions-updater   11,3 MB
```

Once contenedores y 2,5 GB libres. El coste de no compartir nada es
despreciable.

## Qué hay montado

```
/share/Container/champions-updater/
├── Dockerfile  docker-compose.yml  entrypoint.sh  .env
├── repo/       clon del repositorio (de ahí sale el código)
├── estado/     champions2627.json de trabajo · champions.log · salud.json · ssh/
└── publico/    copia del JSON para servirlo en directo
```

El demonio **no reimplementa nada**: ejecuta `scripts/update_champions.py`
—el mismo fichero que usa el workflow suplente— como subproceso, sacado del
clon. Actualizarlo es un `git push` desde el Mac y un `docker restart`.

## Los dos modos

**`sombra`**: trabaja sobre su propia copia en `/estado`, no publica, y después
de cada ciclo compara lo que él generaría con lo que hay publicado. En el log
una línea `≠` significa desviación.

**`produccion`** (el actual): publica él. Cada ciclo parte del remoto
(`rebase --abort` + `fetch` + `checkout -B main origin/main`), así que no puede
atascarse con un conflicto. Empuja por SSH con una clave de despliegue guardada
en `estado/ssh/` y dada de alta en el repositorio.

No publica cuando lo único que ha cambiado es `lastUpdated`: el updater
reescribe esa marca en cada pasada y, a 60 segundos por ciclo, serían más de
mil commits diarios sin un solo dato nuevo.

El modo se cambia en el `.env` del NAS:

```
CHAMPIONS_MODO=produccion     # sombra para volver a observar sin publicar
```

## Uso diario

```bash
./nas/comprobar-nas.sh          # no toca nada
```

```bash
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; docker logs -f champions-updater'
```

Tras un `git push` con cambios en el demonio o en el updater basta reiniciar,
porque el entrypoint hace `fetch` al arrancar:

```bash
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; docker restart champions-updater'
```

Si el cambio toca el `Dockerfile` o el `entrypoint.sh`, que viajan dentro de la
imagen, hay que reconstruirla — y **con `DOCKER_BUILDKIT=0`**: el BuildKit de
Container Station falla al montar los datasets de las capas y ni siquiera llega
a leer el Dockerfile. Lo hace ya `instalar.sh`.

## Volver atrás

```bash
ssh nas 'sed -i s/produccion/sombra/ /share/Container/champions-updater/.env'
ssh nas 'export DOCKER_HOST=unix:///var/run/docker.sock; export PATH=/share/ZFS530_DATA/.qpkg/container-station/bin:$PATH; cd /share/Container/champions-updater && docker compose up -d'
```

El NAS deja de publicar, los datos envejecen y en veinte minutos el workflow
suplente toma el relevo solo. No hay que tocar nada en GitHub.

Para quitarlo del todo, `docker compose down` en esa carpeta y borrarla. No
hace falta tocar nada de La Liga.

## Lo que queda pendiente

- **El techo de los cinco minutos.** La app lee el JSON de
  `raw.githubusercontent.com`, cuya CDN cachea unos cinco minutos. Da igual que
  el NAS publique cada 60 segundos. Romper ese techo pasa por servir el JSON
  desde `laliga-api`, y eso **sí toca el servicio de La Liga**: es una ruta
  nueva y aditiva en `server.js`, pero hay que hacerla con copia de seguridad y
  comprobando después que los avisos de La Liga siguen en pie. Está sin hacer a
  propósito. La app ya lo contempla: pide primero al NAS con cuatro segundos de
  margen y cae a GitHub sin enterarse.

- **Avisos en vivo de la Champions.** La app ya sabe darse de alta contra
  `/champions/register`, pero esa ruta no existe todavía y el sondeador que
  manda los avisos (`poller.js`) vive solo dentro del NAS. Mientras tanto, el
  recordatorio antes del saque funciona igual porque lo programa el propio
  teléfono.

- **Un aviso cuando el NAS se caiga.** Hoy hay que mirar el historial de
  commits: ver un `github-actions[bot]` significa que el NAS estuvo caído.

## Nota sobre `cornellanas.net`

El 29/08/26, montando esto, `laliga-api.cornellanas.net` dejó de responder
desde fuera. **No tenía nada que ver con el NAS**: el dominio entero
—incluida su raíz— era inalcanzable, fallaba igual desde el propio NAS, y el
`traceroute` moría en Telefónica. Es el rango de Cloudflare `188.114.96.0/24`,
que no se alcanzaba desde esta conexión; `cornellana.online`, que cae en otro
rango, funcionaba con normalidad. El servicio estaba sano todo el rato: desde
dentro del NAS respondía `{"status":"ok"}` tanto por `localhost:8090` como por
`192.168.1.66:8090`, que es por donde entra el túnel.
