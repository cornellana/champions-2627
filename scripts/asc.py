#!/usr/bin/env python3
"""
asc.py — trato con App Store Connect para esta app.

Reutiliza la clave de API que ya está dada de alta en el Mac
(`~/.appstoreconnect/`, la misma con la que se publicó Control Tiempos
Eclipse). No pide contraseñas ni abre la web.

Órdenes:

    python3 scripts/asc.py estado      qué hay dado de alta ahora mismo
    python3 scripts/asc.py crear       registra el bundle ID y crea la ficha
    python3 scripts/asc.py testflight  builds subidas y su estado de proceso

El identificador de app y el nombre de la ficha se leen de las constantes de
abajo, para que cambiarlos sea una línea y no una búsqueda por el fichero.
"""

from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

API = "https://api.appstoreconnect.apple.com"
CONFIG = Path.home() / ".appstoreconnect" / "config.json"
KEYS_DIR = Path.home() / ".appstoreconnect" / "private_keys"

BUNDLE_ID = "com.cornellana.Champions"

# Nombre de la ficha en la tienda.
#
# NO se llama «Champions League»: es una marca registrada de UEFA y la propia
# App Store Connect rechaza el alta, además de exponer a una reclamación. Se usa
# el mote popular del trofeo, que no está registrado como marca de competición.
# Dentro del teléfono la app se sigue llamando Champions.
APP_NAME = "Orejona"

# El SKU es interno, solo lo ve el titular de la cuenta.
SKU = "orejona-2627"

PRIMARY_LOCALE = "es-ES"


# -- Autenticación --------------------------------------------------------

def token() -> str:
    """JWT de 20 minutos firmado con la clave privada de la cuenta."""
    if not CONFIG.exists():
        sys.exit(f"Falta {CONFIG}")
    cfg = json.loads(CONFIG.read_text())
    key_path = KEYS_DIR / f"AuthKey_{cfg['key_id']}.p8"
    if not key_path.exists():
        sys.exit(f"Falta la clave privada {key_path}")

    return jwt.encode(
        {
            "iss": cfg["issuer_id"],
            "exp": int(time.time()) + 20 * 60,
            "aud": "appstoreconnect-v1",
        },
        key_path.read_text(),
        algorithm="ES256",
        headers={"kid": cfg["key_id"], "typ": "JWT"},
    )


def llamar(metodo: str, ruta: str, cuerpo: dict | None = None) -> dict:
    datos = json.dumps(cuerpo).encode() if cuerpo else None
    req = urllib.request.Request(
        API + ruta,
        data=datos,
        method=metodo,
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            texto = r.read().decode()
            return json.loads(texto) if texto else {}
    except urllib.error.HTTPError as e:
        detalle = e.read().decode()
        try:
            errores = json.loads(detalle).get("errors", [])
            mensaje = "\n".join(
                f"  · {x.get('title')}: {x.get('detail')}" for x in errores
            )
        except json.JSONDecodeError:
            mensaje = "  " + detalle[:500]
        raise SystemExit(f"HTTP {e.code} en {metodo} {ruta}\n{mensaje}") from None


# -- Consultas ------------------------------------------------------------

def buscar_bundle() -> dict | None:
    r = llamar("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE_ID}&limit=200")
    for item in r.get("data", []):
        if item["attributes"]["identifier"] == BUNDLE_ID:
            return item
    return None


def buscar_app() -> dict | None:
    r = llamar("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}&limit=200")
    datos = r.get("data", [])
    return datos[0] if datos else None


def cmd_estado() -> None:
    print(f"Bundle ID  {BUNDLE_ID}")
    bundle = buscar_bundle()
    if bundle:
        print(f"  ✅ registrado (id {bundle['id']}, "
              f"nombre «{bundle['attributes'].get('name')}»)")
    else:
        print("  ❌ sin registrar")

    app = buscar_app()
    if not app:
        print("\nFicha de app: ❌ no existe")
        print("   → `python3 scripts/asc.py crear`")
        return

    a = app["attributes"]
    print(f"\nFicha de app: ✅ «{a.get('name')}»")
    print(f"  Apple ID   {app['id']}")
    print(f"  SKU        {a.get('sku')}")
    print(f"  Idioma     {a.get('primaryLocale')}")
    print(f"  https://appstoreconnect.apple.com/apps/{app['id']}/testflight/ios")


def cmd_crear() -> None:
    bundle = buscar_bundle()
    if bundle:
        print(f"Bundle ID ya registrado (id {bundle['id']})")
    else:
        print(f"Registrando {BUNDLE_ID}…")
        r = llamar("POST", "/v1/bundleIds", {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": BUNDLE_ID,
                    "name": APP_NAME,
                    "platform": "IOS",
                },
            }
        })
        bundle = r["data"]
        print(f"  ✅ registrado (id {bundle['id']})")

    # La app necesita el permiso de avisos por APNs: se activa en el bundle.
    activar_push(bundle["id"])

    app = buscar_app()
    if app:
        print(f"Ficha ya creada: «{app['attributes']['name']}» "
              f"(Apple ID {app['id']})")
        return

    # Apple **no deja crear fichas de app por API**: `/v1/apps` solo admite
    # GET y UPDATE. Comprobado el 29/08/2026 — devuelve 403 «The resource
    # \'apps\' does not allow \'CREATE\'». Hay que darla de alta a mano una vez;
    # todo lo demás (subir builds, repartir a probadores) sí va por API.
    print(f"""
La ficha hay que crearla a mano: la API de Apple no lo permite.

  1. https://appstoreconnect.apple.com/apps  →  «+»  →  Nueva app
  2. Plataforma  iOS
     Nombre      {APP_NAME}
     Idioma      Español (España)
     Bundle ID   {BUNDLE_ID}
     SKU         {SKU}
     Acceso      Acceso completo
  3. Volver aquí:  python3 scripts/asc.py estado

Un par de minutos. Después, `scripts/subir_testflight.sh` sube la build.
""")


def activar_push(bundle_uuid: str) -> None:
    """Activa la capacidad de notificaciones push en el bundle ID."""
    try:
        llamar("POST", "/v1/bundleIdCapabilities", {
            "data": {
                "type": "bundleIdCapabilities",
                "attributes": {"capabilityType": "PUSH_NOTIFICATIONS"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_uuid}}
                },
            }
        })
        print("  ✅ notificaciones push activadas")
    except SystemExit as e:
        # Ya estaba activada: no es un fallo.
        if "already exists" in str(e).lower() or "409" in str(e):
            print("  · las notificaciones push ya estaban activadas")
        else:
            print(f"  ⚠️  no se pudo activar push:\n{e}")


def cmd_testflight() -> None:
    app = buscar_app()
    if not app:
        sys.exit("La ficha no existe todavía: `python3 scripts/asc.py crear`")

    r = llamar("GET", f"/v1/builds?filter[app]={app['id']}&limit=20"
                      "&sort=-version&include=preReleaseVersion")
    builds = r.get("data", [])
    if not builds:
        print("Todavía no hay ninguna build subida.")
        return

    versiones = {i["id"]: i["attributes"]["version"]
                 for i in r.get("included", [])
                 if i["type"] == "preReleaseVersions"}

    print(f"Builds de «{app['attributes']['name']}»:\n")
    for b in builds:
        a = b["attributes"]
        rel = b.get("relationships", {}).get("preReleaseVersion", {}).get("data")
        version = versiones.get(rel["id"], "?") if rel else "?"
        print(f"  {version} ({a.get('version')})  "
              f"{a.get('processingState')}  "
              f"caduca: {a.get('expirationDate', '—')}")


ORDENES = {"estado": cmd_estado, "crear": cmd_crear, "testflight": cmd_testflight}

if __name__ == "__main__":
    orden = sys.argv[1] if len(sys.argv) > 1 else "estado"
    if orden not in ORDENES:
        sys.exit(f"Órdenes: {', '.join(ORDENES)}")
    ORDENES[orden]()
