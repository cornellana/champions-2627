#!/usr/bin/env python3
"""
Actualizador continuo de la Champions para el NAS.

Es hermano del de La Liga (`27/nas/laliga_daemon.py`) y hereda sus cicatrices:
partir siempre del remoto, no publicar cuando lo único que cambia es la marca
de tiempo, escritura atómica del fichero servido, y sueño troceado para que una
señal no tenga que esperar diez minutos.

**Es una copia y no un módulo compartido, a propósito.** El de La Liga lleva
publicando desde el 22/08/26 y es el titular de una competición en marcha;
convertirlo en librería a mitad de temporada para ahorrarse trescientas líneas
es cambiar riesgo real por elegancia. Cada competición tiene su contenedor, su
clon y su fichero: si esto se rompe, La Liga no se entera.

No llama a ESPN por su cuenta: ejecuta `scripts/update_champions.py`, el mismo
que usa GitHub Actions como suplente, en un subproceso. Así no hay dos copias
de la lógica de datos, y un fallo en un ciclo no se lleva por delante al
demonio.

Variables de entorno (todas con un valor por defecto razonable):
    CHAMPIONS_MODO              sombra | produccion            (sombra)
    CHAMPIONS_REPO              clon del repositorio           (/repo)
    CHAMPIONS_DATOS             JSON de trabajo en sombra      (<estado>/…)
    CHAMPIONS_INTERVALO_VIVO    segundos entre ciclos con partido   (60)
    CHAMPIONS_INTERVALO_REPOSO  segundos entre ciclos sin partido   (600)
    CHAMPIONS_ESTADO_DIR        carpeta de estado              (/estado)
    CHAMPIONS_PUBLICAR_EN       carpeta donde dejar el JSON servido (opcional)
"""

import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone

BASE = os.path.dirname(os.path.abspath(__file__))

MODO = os.environ.get("CHAMPIONS_MODO", "sombra").strip().lower()
REPO = os.environ.get("CHAMPIONS_REPO", "/repo")
UPDATER = os.path.join(REPO, "scripts", "update_champions.py")
DATOS_REPO = os.path.join(REPO, "data", "champions2627.json")

ESTADO_DIR = os.environ.get("CHAMPIONS_ESTADO_DIR", "/estado")
os.makedirs(ESTADO_DIR, exist_ok=True)

DATOS_SOMBRA = os.environ.get("CHAMPIONS_DATOS",
                              os.path.join(ESTADO_DIR, "champions2627.json"))
INTERVALO_VIVO = int(os.environ.get("CHAMPIONS_INTERVALO_VIVO", "60"))
INTERVALO_REPOSO = int(os.environ.get("CHAMPIONS_INTERVALO_REPOSO", "600"))
LOG = os.environ.get("CHAMPIONS_LOG", os.path.join(ESTADO_DIR, "champions.log"))
SALUD = os.path.join(ESTADO_DIR, "salud.json")
BANDERA_ACTIVOS = os.path.join(ESTADO_DIR, "activos.flag")
PUBLICAR_EN = os.environ.get("CHAMPIONS_PUBLICAR_EN", "").strip()

PUBLICADO_URL = ("https://raw.githubusercontent.com/cornellana/"
                 "champions-2627/main/data/champions2627.json")
FICHERO_SERVIDO = "champions2627.json"

# El updater tarda un par de segundos en reposo y unos veinte con seis partidos
# en directo. 240 es un tope generoso para que una llamada colgada a ESPN no
# congele el ciclo para siempre.
TOPE_UPDATER_SEGUNDOS = 240
TOPE_LOG_BYTES = 5 * 1024 * 1024

_parar = False


def _senal(num, _frame):
    global _parar
    _parar = True
    registrar(f"Recibida señal {num}: terminando al acabar el ciclo.")


def ahora():
    return datetime.now(timezone.utc)


def registrar(mensaje):
    """Una línea al log y a la salida. El log se trunca solo si engorda."""
    linea = f"{ahora().strftime('%Y-%m-%d %H:%M:%S')}Z  {mensaje}"
    print(linea, flush=True)
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > TOPE_LOG_BYTES:
            with open(LOG, encoding="utf-8", errors="replace") as f:
                cola = f.readlines()[-2000:]
            with open(LOG, "w", encoding="utf-8") as f:
                f.writelines(cola)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(linea + "\n")
    except OSError as e:
        print(f"(no se pudo escribir el log: {e})", flush=True)


def fichero_de_datos():
    return DATOS_REPO if MODO == "produccion" else DATOS_SOMBRA


def git(*args):
    """git dentro del clon. Devuelve (ok, salida)."""
    try:
        r = subprocess.run(["git", "-C", REPO, *args],
                           capture_output=True, text=True, timeout=120)
        return r.returncode == 0, ((r.stdout or "") + (r.stderr or "")).strip()
    except (subprocess.TimeoutExpired, OSError) as e:
        return False, str(e)


def sincronizar_con_remoto():
    """Partir siempre del remoto.

    Si un push anterior se cruzó con el workflow suplente, se descarta el
    intento: el JSON se reconstruye entero en cada pasada, así que no hay nada
    que conservar y así no puede haber un conflicto que deje marcadores de
    merge dentro del fichero de datos.
    """
    git("rebase", "--abort")
    ok, salida = git("fetch", "-q", "origin", "main")
    if not ok:
        registrar(f"⚠️  fetch falló: {salida[:200]}")
        return False
    ok, salida = git("checkout", "-q", "-B", "main", "origin/main")
    if not ok:
        registrar(f"⚠️  no se pudo situar main sobre origin/main: {salida[:200]}")
    return ok


def ejecutar_updater():
    """Lanza scripts/update_champions.py. Devuelve (ok, líneas interesantes)."""
    entorno = dict(os.environ)
    entorno["ACTIVE_FLAG_FILE"] = BANDERA_ACTIVOS
    entorno["CHAMPIONS_DATA_FILE"] = fichero_de_datos()
    entorno.setdefault("PRE_MATCH_MINUTES", "45")
    entorno["FORCE_REFRESH"] = "false"
    try:
        r = subprocess.run([sys.executable, UPDATER], capture_output=True,
                           text=True, timeout=TOPE_UPDATER_SEGUNDOS, env=entorno)
    except subprocess.TimeoutExpired:
        return False, [f"el updater no terminó en {TOPE_UPDATER_SEGUNDOS}s; "
                       "se reintenta en el siguiente ciclo"]
    except OSError as e:
        return False, [f"no se pudo lanzar el updater: {e}"]

    salida = (r.stdout or "") + (r.stderr or "")
    interesantes = [l for l in salida.splitlines()
                    if any(m in l for m in ("En juego", "Sin partidos", "⚠", "Error",
                                            "Traceback", "nuevo en el calendario",
                                            "global de la eliminatoria", "✅"))]
    return r.returncode == 0, interesantes or ["(sin novedades)"]


def publicar():
    """Commit y push. Si el push se cruza, el siguiente ciclo republica."""
    ruta = f"data/{FICHERO_SERVIDO}"
    ok, _ = git("add", ruta)
    if not ok:
        return False
    sin_cambios, _ = git("diff", "--cached", "--quiet")
    if sin_cambios:
        return False

    # El updater reescribe `lastUpdated` en cada pasada, así que el fichero
    # SIEMPRE difiere aunque no haya cambiado un solo dato. A 60 segundos por
    # ciclo serían más de mil commits diarios sin información nueva.
    _, diferencias = git("diff", "--cached", "-U0", "--", ruta)
    reales = [l for l in diferencias.splitlines()
              if l[:1] in ("+", "-") and l[:3] not in ("+++", "---")
              and "lastUpdated" not in l]
    if not reales:
        git("reset", "-q", "HEAD", "--", ruta)
        git("checkout", "--", ruta)
        return False

    marca = ahora().strftime("%Y-%m-%dT%H:%M:%SZ")
    git("commit", "-q", "-m", f"chore: actualización automática Champions {marca}")
    ok, _ = git("push", "-q")
    if not ok:
        registrar("Push rechazado (el suplente se adelantó); "
                  "el siguiente ciclo republica sobre el remoto.")
        return False
    return True


def copiar_a_servido():
    """Deja el JSON donde lo sirve el NAS, si se ha configurado esa carpeta."""
    if not PUBLICAR_EN:
        return
    try:
        os.makedirs(PUBLICAR_EN, exist_ok=True)
        destino = os.path.join(PUBLICAR_EN, FICHERO_SERVIDO)
        temporal = destino + ".tmp"
        with open(fichero_de_datos(), "rb") as origen, open(temporal, "wb") as sal:
            sal.write(origen.read())
        # Atómico: nadie lee un fichero a medias.
        os.replace(temporal, destino)
    except OSError as e:
        registrar(f"⚠️  no se pudo copiar a {PUBLICAR_EN}: {e}")


def resumen_de_hoy(ruta_o_datos):
    """{clave: (resultado, minuto, estado, nº sucesos)} de los partidos de hoy."""
    try:
        if isinstance(ruta_o_datos, dict):
            datos = ruta_o_datos
        else:
            with open(ruta_o_datos, encoding="utf-8") as f:
                datos = json.load(f)
    except (OSError, ValueError):
        return {}
    hoy = ahora().strftime("%Y-%m-%d")
    resumen = {}
    for dia in datos.get("matchDays", []):
        if dia.get("date") != hoy:
            continue
        for g in dia.get("games", []):
            sucesos = ((g.get("details") or {}).get("events") or [])
            resumen[f"{g.get('home')}-{g.get('away')}"] = (
                g.get("result"), g.get("clock"), g.get("state"), len(sucesos))
    return resumen


def comparar_con_publicado():
    """Modo sombra: ¿lo que yo generaría coincide con lo que ve la app?"""
    try:
        with urllib.request.urlopen(PUBLICADO_URL, timeout=20) as r:
            publicado = json.loads(r.read().decode("utf-8"))
    except Exception as e:
        registrar(f"   (no se pudo leer lo publicado: {e})")
        return

    mio = resumen_de_hoy(fichero_de_datos())
    suyo = resumen_de_hoy(publicado)
    if not mio and not suyo:
        return
    for clave in sorted(set(mio) | set(suyo)):
        a, b = mio.get(clave), suyo.get(clave)
        if a == b:
            registrar(f"   ≡ {clave}: {a[0]} {a[1] or ''} ({a[3]} sucesos) — coincide")
        else:
            registrar(f"   ≠ {clave}: yo {a} · publicado {b}")


def escribir_salud(ciclo, activo, ok):
    """Marca de vida. La lee el HEALTHCHECK del contenedor."""
    try:
        with open(SALUD, "w", encoding="utf-8") as f:
            json.dump({
                "actualizado": ahora().strftime("%Y-%m-%dT%H:%M:%SZ"),
                "pid": os.getpid(),
                "competicion": "uefa.champions",
                "modo": MODO,
                "ciclo": ciclo,
                "partidos_activos": activo,
                "ultimo_ciclo_ok": ok,
            }, f, ensure_ascii=False, indent=2)
    except OSError as e:
        registrar(f"⚠️  no se pudo escribir {SALUD}: {e}")


def dormir(segundos):
    """Sueño troceado: una señal no tiene que esperar diez minutos."""
    fin = time.time() + segundos
    while time.time() < fin and not _parar:
        time.sleep(min(2, max(0, fin - time.time())))


def comprobaciones_previas():
    problemas = []
    if MODO not in ("sombra", "produccion"):
        problemas.append(f"CHAMPIONS_MODO='{MODO}' no es ni sombra ni produccion")
    if not os.path.isfile(UPDATER):
        problemas.append(f"no encuentro el updater en {UPDATER}")
    if MODO == "produccion" and not os.path.isdir(os.path.join(REPO, ".git")):
        problemas.append(f"{REPO} no es un clon de git y en producción hace falta")
    if MODO == "sombra":
        os.makedirs(os.path.dirname(DATOS_SOMBRA), exist_ok=True)
        if not os.path.exists(DATOS_SOMBRA):
            # Sin punto de partida el updater solo reconstruiría los nueve días
            # de su ventana y perdería el resto del calendario.
            try:
                with urllib.request.urlopen(PUBLICADO_URL, timeout=30) as r:
                    contenido = r.read()
                with open(DATOS_SOMBRA, "wb") as f:
                    f.write(contenido)
                registrar(f"Copia inicial descargada en {DATOS_SOMBRA}")
            except Exception as e:
                problemas.append(f"no pude descargar la copia inicial: {e}")
    return problemas


def main():
    signal.signal(signal.SIGTERM, _senal)
    signal.signal(signal.SIGINT, _senal)

    registrar("═" * 60)
    registrar(f"Demonio Champions arrancado · modo {MODO.upper()} · pid {os.getpid()}")
    registrar(f"   updater: {UPDATER}")
    registrar(f"   datos:   {fichero_de_datos()}")
    registrar(f"   ritmo:   {INTERVALO_VIVO}s con partido · {INTERVALO_REPOSO}s sin partido")
    if MODO == "sombra":
        registrar("   NO publica nada: solo compara con lo que hay en GitHub.")

    problemas = comprobaciones_previas()
    if problemas:
        for p in problemas:
            registrar(f"✗ {p}")
        return 1

    ciclo = 0
    while not _parar:
        ciclo += 1
        if MODO == "produccion":
            sincronizar_con_remoto()

        ok, lineas = ejecutar_updater()
        activo = os.path.exists(BANDERA_ACTIVOS)
        registrar(f"{'✓' if ok else '✗'} ciclo {ciclo} · "
                  f"{'PARTIDO EN JUEGO' if activo else 'en reposo'}")
        for l in lineas:
            registrar(f"   {l.strip()}")

        if ok and MODO == "produccion":
            # La copia servida se hace ANTES de publicar, a propósito.
            #
            # `publicar()` revierte el fichero cuando lo único que ha cambiado
            # es `lastUpdated` —para no llenar el repositorio de commits sin
            # dato nuevo—, y esa reversión se llevaba por delante la marca
            # fresca. Copiando después, el NAS servía datos con la fecha del
            # último cambio REAL, que en reposo puede ser de hace medio día, y
            # la app los daba por caducados teniéndolos recién comprobados.
            copiar_a_servido()
            if publicar():
                registrar("   publicado en GitHub")
        elif ok:
            comparar_con_publicado()

        escribir_salud(ciclo, activo, ok)
        if _parar:
            break
        dormir(INTERVALO_VIVO if activo else INTERVALO_REPOSO)

    registrar(f"Demonio detenido tras {ciclo} ciclos.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
