#!/usr/bin/env python3
"""
update_champions.py

Actualiza `data/champions2627.json` con lo que va pasando: marcadores en
directo, alineaciones, goles y tarjetas, estadísticas de equipo, tandas de
penaltis y el global de cada eliminatoria. También rehace la clasificación de
la fase liga y las tablas de goleadores y asistentes.

Lo ejecuta el demonio del NAS cada 60 segundos mientras hay fútbol y cada diez
minutos el resto del tiempo; GitHub Actions lo usa igual como suplente. Es el
mismo fichero en los dos sitios a propósito: dos copias de esta lógica
acabarían divergiendo.

    python3 scripts/update_champions.py
    FORCE_REFRESH=true python3 scripts/update_champions.py

Variables de entorno:
    CHAMPIONS_DATA_FILE   JSON sobre el que trabajar (por defecto data/…)
    ACTIVE_FLAG_FILE      fichero-señal de "hay partido"; lo lee el demonio
    FORCE_REFRESH         rehace los detalles de los partidos ya cerrados
    PRE_MATCH_MINUTES     margen previo al saque que cuenta como activo (45)
    POST_KICKOFF_MINUTES  margen posterior al saque que cuenta como activo (20)
"""

from __future__ import annotations

import json
import os
import sys
import unicodedata
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import requests

# ── Configuración ────────────────────────────────────────────────────────────

BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions"
ESPN_SCOREBOARD = f"{BASE}/scoreboard"
ESPN_SUMMARY = f"{BASE}/summary"
ESPN_STANDINGS = "https://site.api.espn.com/apis/v2/sports/soccer/uefa.champions/standings"

SEASON_YEAR = 2026
MADRID = ZoneInfo("Europe/Madrid")
TIMEOUT = 30

DATA_FILE = os.environ.get("CHAMPIONS_DATA_FILE") or os.path.join(
    os.path.dirname(__file__), "..", "data", "champions2627.json")

FORCE_REFRESH = os.environ.get("FORCE_REFRESH", "false").lower() == "true"

# El demonio consulta este fichero para decidir si sigue con ritmo corto o se
# echa a dormir diez minutos.
ACTIVE_FLAG_FILE = os.environ.get("ACTIVE_FLAG_FILE", "")

# Margen antes del saque durante el cual el partido ya cuenta como activo.
PRE_MATCH_MINUTES = int(os.environ.get("PRE_MATCH_MINUTES", "45"))

# Y margen DESPUÉS de la hora de inicio. Sin esto, un partido que ESPN todavía
# marca como `pre` un minuto después del saque apaga el bucle justo cuando más
# falta hace. Le pasó a la app de La Liga el 20/08/26 y no hay por qué repetirlo.
POST_KICKOFF_MINUTES = int(os.environ.get("POST_KICKOFF_MINUTES", "20"))

# Ventana de días que se consulta en cada pasada. Cubre los aplazamientos y los
# partidos que se cierran de madrugada sin barrer la temporada entera.
DIAS_ATRAS, DIAS_ADELANTE = 4, 5


# ── Nombres de club: ESPN → nombre canónico de la app ────────────────────────
#
# Si aquí se cuela un nombre que la app no conoce, ese equipo se queda sin
# escudo, sin traducción y sin plantilla. El script avisa cuando ve uno nuevo.

TEAM_NAME_MAP: dict[str, str] = {
    "AEK Athens": "AEK Atenas",
    "AS Roma": "Roma", "Roma": "Roma",
    "Arsenal": "Arsenal",
    "Aston Villa": "Aston Villa",
    "Atletico Madrid": "Atlético de Madrid",
    "Atlético Madrid": "Atlético de Madrid",
    "Atlético de Madrid": "Atlético de Madrid",
    "Barcelona": "FC Barcelona", "FC Barcelona": "FC Barcelona",
    "Bayern Munich": "Bayern de Múnich", "Bayern München": "Bayern de Múnich",
    "Bodo/Glimt": "Bodø/Glimt", "Bodø/Glimt": "Bodø/Glimt",
    "Borussia Dortmund": "Borussia Dortmund", "Dortmund": "Borussia Dortmund",
    "Club Brugge": "Brujas", "Club Brugge KV": "Brujas",
    "Como": "Como",
    "FC Porto": "Oporto", "Porto": "Oporto",
    "Fenerbahce": "Fenerbahçe", "Fenerbahçe": "Fenerbahçe",
    "Feyenoord Rotterdam": "Feyenoord", "Feyenoord": "Feyenoord",
    "Galatasaray": "Galatasaray",
    "Internazionale": "Inter de Milán", "Inter Milan": "Inter de Milán",
    "Inter": "Inter de Milán",
    "LASK Linz": "LASK", "LASK": "LASK",
    "Lens": "Lens", "RC Lens": "Lens",
    "Lille": "Lille", "Lille OSC": "Lille",
    "Liverpool": "Liverpool",
    "Manchester City": "Manchester City", "Man City": "Manchester City",
    "Manchester United": "Manchester United", "Man United": "Manchester United",
    "Napoli": "Nápoles",
    "PSV Eindhoven": "PSV", "PSV": "PSV",
    "Paris Saint-Germain": "Paris Saint-Germain",
    # Dentro del texto de los sucesos ESPN lo escribe sin guiones, y sin esta
    # línea los cambios y las tarjetas del PSG se quedaban sin equipo.
    "Paris Saint Germain": "Paris Saint-Germain",
    "PSG": "Paris Saint-Germain",
    "RB Leipzig": "RB Leipzig",
    "Real Betis": "Real Betis",
    "Real Madrid": "Real Madrid",
    "Sabah FK": "Sabah", "Sabah": "Sabah",
    "Shakhtar Donetsk": "Shajtar Donetsk",
    "Slavia Prague": "Slavia de Praga",
    "Slovan Bratislava": "Slovan Bratislava",
    "Sporting CP": "Sporting de Portugal", "Sporting Lisbon": "Sporting de Portugal",
    "VfB Stuttgart": "Stuttgart",
    "Viking FK": "Viking", "Viking": "Viking",
    "Villarreal": "Villarreal",
}

EQUIPOS_CONOCIDOS = set(TEAM_NAME_MAP.values())

# Nombres desconocidos ya avisados en esta pasada. Sin esto, un club que ESPN
# escriba de otra forma llena el log con la misma línea siete veces por partido.
_desconocidos_avisados: set[str] = set()


# ── Fases ────────────────────────────────────────────────────────────────────

FASES_POR_ETIQUETA = {
    "league phase": "league",
    "knockout round playoffs": "playoff",
    "rd of 16": "r16",
    "round of 16": "r16",
    "quarterfinals": "qf",
    "semifinals": "sf",
    "final": "final",
}

FASES_ELIMINATORIA = ("playoff", "r16", "qf", "sf")


# ── Sucesos ──────────────────────────────────────────────────────────────────
#
# ESPN identifica los `keyEvents` con ids numéricos, no con nombres. Los goles
# no tienen un id fijo, se reconocen por `scoringPlay`. Estos ids están
# verificados sobre partidos reales de la competición.

TIPOS_SIN_GOL = {
    "76": "SUBSTITUTION",
    "94": "YELLOW_CARD",
    "93": "RED_CARD",
    "114": "MISSED_PENALTY",   # penalti parado
    "140": "MISSED_PENALTY",   # penalti al palo
}
IDS_TARJETA = ("93", "94")
ID_GOL_EN_PROPIA = "97"
ID_PENALTI = "98"

# Estadísticas de equipo que se publican. La lista es cerrada a propósito: la
# app las traduce por clave y una que no esté en el catálogo saldría en crudo.
ESTADISTICAS = [
    "possessionPct", "totalShots", "shotsOnTarget", "wonCorners",
    "foulsCommitted", "offsides", "yellowCards", "redCards",
    "saves", "accuratePasses", "passPct",
]


# ── Utilidades ───────────────────────────────────────────────────────────────

def ahora_utc() -> datetime:
    return datetime.now(timezone.utc)


def fecha_hora_madrid(utc_iso: str) -> tuple[str, str]:
    """Del timestamp UTC de ESPN a (fecha, hora) local de Madrid.

    Se usa `zoneinfo` y no un desfase fijo: el cambio de hora cae en marzo y
    octubre, justo en mitad de la competición.
    """
    dt = datetime.fromisoformat(utc_iso.replace("Z", "+00:00")).astimezone(MADRID)
    return dt.strftime("%Y-%m-%d"), dt.strftime("%H:%M")


def plegar(texto: str) -> str:
    """Minúsculas y sin acentos, para comparar nombres con holgura."""
    sin_tildes = unicodedata.normalize("NFKD", texto or "")
    return "".join(c for c in sin_tildes if not unicodedata.combining(c)).lower().strip()


def normalizar_equipo(nombre: str | None) -> str | None:
    if not nombre:
        return None
    limpio = nombre.strip()
    if limpio in TEAM_NAME_MAP:
        return TEAM_NAME_MAP[limpio]
    # Segundo intento sin acentos ni mayúsculas, por si ESPN cambia la grafía.
    objetivo = plegar(limpio)
    for espn, canonico in TEAM_NAME_MAP.items():
        if plegar(espn) == objetivo:
            return canonico
    if limpio not in _desconocidos_avisados:
        _desconocidos_avisados.add(limpio)
        print(f"  ⚠️  equipo desconocido en ESPN: «{limpio}» — "
              f"sin escudo ni traducción hasta que se añada al mapa")
    return limpio


def resolver_equipo(nombre: str | None, local: str, visitante: str) -> str | None:
    """Asigna el nombre suelto de un suceso a uno de los dos equipos del partido."""
    if not nombre:
        return None
    n = plegar(normalizar_equipo(nombre) or nombre)
    for equipo in (local, visitante):
        e = plegar(equipo)
        if e and (e == n or e in n or n in e):
            return equipo
    return None


def partir_reloj(display: str | None) -> tuple[int, int | None]:
    """`"90'+9'"` → (90, 9) · `"23'"` → (23, None) · `""` → (0, None)."""
    limpio = (display or "").replace("'", "").strip()
    if not limpio:
        return 0, None
    if "+" in limpio:
        base, _, extra = limpio.partition("+")
        base, extra = base.strip(), extra.strip()
        return (int(base) if base.isdigit() else 0,
                int(extra) if extra.isdigit() else None)
    return (int(limpio) if limpio.isdigit() else 0), None


# ── Cliente HTTP ─────────────────────────────────────────────────────────────

def pedir(url: str, params: dict | None = None) -> dict | None:
    try:
        r = requests.get(url, params=params, timeout=TIMEOUT)
        r.raise_for_status()
        return r.json()
    except (requests.RequestException, ValueError) as e:
        print(f"  ⚠️  {url.rsplit('/', 1)[-1]}: {e}")
        return None


# ── Extracción de texto de los sucesos ───────────────────────────────────────

def equipo_del_texto(texto: str | None, tipo: str) -> str | None:
    """ESPN deja `team` a nulo en muchos sucesos; el nombre va dentro del texto."""
    if not texto:
        return None
    if tipo == "76" and texto.startswith("Substitution, "):
        return texto[len("Substitution, "):].split(". ")[0] or None
    if tipo in IDS_TARJETA and "(" in texto and ")" in texto:
        return texto[texto.index("(") + 1:texto.index(")")] or None
    return None


def jugador_del_texto(texto: str | None, tipo: str) -> str | None:
    """Igual con el jugador: `athlete` viene vacío y hay que sacarlo del texto."""
    if not texto:
        return None
    if tipo == ID_GOL_EN_PROPIA:
        if texto.lower().startswith("own goal by "):
            return texto[len("Own Goal by "):].split(",")[0].strip() or None
        return None
    if tipo == "76":
        partes = texto.split(". ")
        if len(partes) > 1:
            return partes[1].split(" replaces ")[0].strip() or None
        return None
    if tipo in IDS_TARJETA:
        return texto[:texto.index("(")].strip() if "(" in texto else None
    # Goles y penaltis fallados llevan el marcador delante:
    # "Goal! Real Madrid 1, Inter 0. Jugador (Real Madrid) right footed shot…"
    partes = texto.split(". ")
    if len(partes) > 1:
        resto = ". ".join(partes[1:])
        if "(" in resto:
            return resto[:resto.index("(")].strip() or None
    return None


def asistente_del_texto(texto: str | None) -> str | None:
    """El pasador del gol.

    ESPN no publica las asistencias como dato aparte, pero el texto del gol
    termina en «Assisted by Fulano». Sacarlo de ahí sale gratis y permite la
    tabla de asistentes sin una sola petición extra.
    """
    if not texto or "Assisted by " not in texto:
        return None
    resto = texto.split("Assisted by ", 1)[1]
    # Corta en el primer punto o coma: detrás suele venir «with a cross» y demás.
    for corte in (".", ","):
        if corte in resto:
            resto = resto.split(corte, 1)[0]
    return resto.strip() or None


def jugador_que_sale(texto: str | None, tipo: str) -> str | None:
    """En un cambio, quién es sustituido."""
    if tipo != "76" or not texto:
        return None
    partes = texto.split(". ")
    if len(partes) > 1:
        trozos = partes[1].split(" replaces ")
        if len(trozos) > 1:
            return trozos[1].strip().strip(".,;:!?") or None
    return None


# ── Actividad ────────────────────────────────────────────────────────────────

def partido_activo(evento: dict, ahora: datetime) -> bool:
    """¿Justifica este partido seguir sondeando cada minuto?"""
    estado = ((evento.get("status") or {}).get("type") or {}).get("state")
    if estado == "in":
        return True
    if estado != "pre":
        return False
    crudo = evento.get("date")
    if not crudo:
        return False
    try:
        saque = datetime.fromisoformat(crudo.replace("Z", "+00:00"))
    except ValueError:
        return False
    faltan = (saque - ahora).total_seconds() / 60
    return -POST_KICKOFF_MINUTES <= faltan <= PRE_MATCH_MINUTES


def escribir_bandera(activo: bool) -> None:
    if not ACTIVE_FLAG_FILE:
        return
    if activo:
        with open(ACTIVE_FLAG_FILE, "w", encoding="utf-8") as f:
            f.write("1")
    elif os.path.exists(ACTIVE_FLAG_FILE):
        os.remove(ACTIVE_FLAG_FILE)


# ── Parseo del partido ───────────────────────────────────────────────────────

def ventanas_de_fase() -> list[tuple[str, datetime, datetime]]:
    """Fechas de cada fase, leídas del propio calendario de ESPN."""
    board = pedir(ESPN_SCOREBOARD)
    if not board:
        return []
    ventanas = []
    for bloque in (board.get("leagues") or [{}])[0].get("calendar") or []:
        for entrada in bloque.get("entries", []) or []:
            fase = FASES_POR_ETIQUETA.get((entrada.get("label") or "").strip().lower())
            if not fase:
                continue
            ventanas.append((
                fase,
                datetime.fromisoformat(entrada["startDate"].replace("Z", "+00:00")),
                datetime.fromisoformat(entrada["endDate"].replace("Z", "+00:00")),
            ))
    return ventanas


def fase_de(utc_iso: str, ventanas: list) -> str:
    dt = datetime.fromisoformat(utc_iso.replace("Z", "+00:00"))
    for fase, inicio, fin in ventanas:
        if inicio <= dt <= fin:
            return fase
    return "final"


def parsear_partido(evento: dict, ventanas: list, previo: dict | None) -> tuple[dict, str] | None:
    """Convierte un evento de ESPN en un partido de nuestro JSON."""
    comp = (evento.get("competitions") or [{}])[0]
    local = visitante = goles_local = goles_visitante = None

    for c in comp.get("competitors", []) or []:
        nombre = normalizar_equipo((c.get("team") or {}).get("displayName"))
        if c.get("homeAway") == "home":
            local, goles_local = nombre, c.get("score")
        else:
            visitante, goles_visitante = nombre, c.get("score")

    if not local or not visitante:
        return None

    estado_tipo = (evento.get("status") or {}).get("type") or {}
    terminado = bool(estado_tipo.get("completed"))
    estado = estado_tipo.get("state")
    en_juego = estado == "in"

    crudo = evento.get("date") or ""
    fecha, hora = fecha_hora_madrid(crudo) if crudo else ("", "--:--")

    sede = comp.get("venue") or {}

    partido = {
        "id": str(evento.get("id") or ""),
        "time": hora,
        "home": local,
        "away": visitante,
        # La fase y la jornada del calendario mandan sobre lo que se deduzca
        # ahora: `fetch_season.py` las calculó con la temporada entera delante y
        # aquí solo se ven nueve días.
        "stage": (previo or {}).get("stage") or fase_de(crudo, ventanas),
        "matchday": (previo or {}).get("matchday"),
        "tieId": (previo or {}).get("tieId"),
        "leg": (previo or {}).get("leg"),
        # El canal se cura a mano; ESPN solo publica el mercado de EE.UU.
        "tv": (previo or {}).get("tv"),
        "done": terminado,
        # El marcador se publica también en directo. `done` sigue queriendo
        # decir "terminado": la clasificación depende de él y un partido en
        # curso no puede contar como jugado.
        "result": (f"{goles_local}-{goles_visitante}"
                   if (terminado or en_juego) and goles_local is not None else None),
        "aggregate": (previo or {}).get("aggregate"),
        "shootout": None,
        "state": estado,
        "clock": ((evento.get("status") or {}).get("displayClock") or None) if en_juego else None,
        "statusText": estado_tipo.get("description") if en_juego else None,
        "stadium": (sede.get("fullName") or "").strip() or (previo or {}).get("stadium"),
        "venueCity": ((sede.get("address") or {}).get("city") or "").strip()
                     or (previo or {}).get("venueCity"),
        "details": None,
    }
    return partido, fecha


def parsear_detalles(resumen: dict | None, local: str, visitante: str) -> dict | None:
    """Alineaciones, sucesos, estadísticas y tanda de penaltis."""
    if not resumen:
        return None

    # ── Sucesos ──
    sucesos = []
    for idx, ev in enumerate(resumen.get("keyEvents") or []):
        tipo = str((ev.get("type") or {}).get("id") or "")
        es_gol = ev.get("scoringPlay") is True
        if not es_gol and tipo not in TIPOS_SIN_GOL:
            continue

        texto = ev.get("text")
        if es_gol:
            if tipo == ID_GOL_EN_PROPIA or (texto or "").lower().startswith("own goal"):
                clase = "OWN_GOAL"
            elif tipo == ID_PENALTI:
                clase = "PENALTY"
            else:
                clase = "GOAL"
        else:
            clase = TIPOS_SIN_GOL[tipo]

        minuto, añadido = partir_reloj((ev.get("clock") or {}).get("displayValue"))
        equipo_crudo = equipo_del_texto(texto, tipo) or (ev.get("team") or {}).get("displayName")

        # En un gol, el segundo jugador es quien asistió; en un cambio, quien sale.
        relacionado = (asistente_del_texto(texto) if es_gol
                       else jugador_que_sale(texto, tipo))

        sucesos.append({
            "id": f"{ev.get('id', '')}_{idx}",
            "type": clase,
            "minute": minuto,
            "extraTime": añadido,
            "playerName": jugador_del_texto(texto, tipo),
            "relatedPlayer": relacionado,
            "teamName": resolver_equipo(equipo_crudo, local, visitante),
            "text": None,
        })

    # ── Alineaciones ──
    alineacion_local = alineacion_visitante = None
    for roster in resumen.get("rosters") or []:
        formacion = roster.get("formation")
        if isinstance(formacion, dict):
            formacion = formacion.get("displayName")

        jugadores = []
        for p in (roster.get("roster") or roster.get("athletes") or []):
            atleta = p.get("athlete") or {}
            nombre = atleta.get("displayName") or atleta.get("fullName") or ""
            if not nombre:
                continue
            dorsal = str(p.get("jersey") or "")
            jugadores.append({
                "id": str(atleta.get("id") or nombre),
                "jersey": int(dorsal) if dorsal.isdigit() else None,
                "name": nombre,
                "position": (p.get("position") or {}).get("abbreviation"),
                "isStarter": bool(p.get("starter", False)),
                "events": None,
                "athleteID": str(atleta.get("id") or "") or None,
            })

        alineacion = {"formation": formacion, "players": jugadores}
        if roster.get("homeAway") == "home":
            alineacion_local = alineacion
        else:
            alineacion_visitante = alineacion

    # ── Estadísticas de equipo ──
    estadisticas = []
    equipos_box = (resumen.get("boxscore") or {}).get("teams") or []
    if len(equipos_box) >= 2:
        por_lado = {}
        for bloque in equipos_box:
            lado = (bloque.get("homeAway")
                    or ("home" if bloque is equipos_box[0] else "away"))
            por_lado[lado] = {s.get("name"): s.get("displayValue")
                              for s in (bloque.get("statistics") or [])}
        for clave in ESTADISTICAS:
            valor_local = (por_lado.get("home") or {}).get(clave)
            valor_visitante = (por_lado.get("away") or {}).get(clave)
            if valor_local is None and valor_visitante is None:
                continue
            estadisticas.append({
                "key": clave,
                "home": str(valor_local if valor_local is not None else "—"),
                "away": str(valor_visitante if valor_visitante is not None else "—"),
            })

    # ── Tanda de penaltis ──
    penaltis = []
    for bloque in resumen.get("shootout") or []:
        equipo = resolver_equipo(bloque.get("team"), local, visitante) or bloque.get("team")
        for tiro in bloque.get("shots") or []:
            penaltis.append({
                "team": equipo,
                "order": int(tiro.get("shotNumber") or 0),
                "player": tiro.get("player") or "",
                "scored": bool(tiro.get("didScore")),
            })

    return {
        "homeLineup": alineacion_local,
        "awayLineup": alineacion_visitante,
        "events": sucesos or None,
        "teamStats": estadisticas or None,
        "penalties": penaltis or None,
    }


def marcador_penaltis(penaltis: list[dict] | None, local: str, visitante: str) -> str | None:
    """`"4-3"` a partir de los lanzamientos, o `None` si no hubo tanda."""
    if not penaltis:
        return None
    a = sum(1 for p in penaltis if p.get("team") == local and p.get("scored"))
    b = sum(1 for p in penaltis if p.get("team") == visitante and p.get("scored"))
    return f"{a}-{b}"


def fusionar_detalles(nuevos: dict | None, previos: dict | None) -> dict | None:
    """Lo nuevo encima de lo viejo, sin perder por el camino lo que ya había.

    En directo se pregunta a ESPN cada minuto y un fallo puntual devuelve un
    resumen a medias. Sin esta mezcla, un tropiezo del proveedor borraría de la
    app los goles y las alineaciones que ya estaban publicados.
    """
    if not nuevos:
        return previos
    if not previos:
        return nuevos
    # Las alineaciones tardan en salir y a veces desaparecen del resumen: se
    # conserva la última buena.
    for campo in ("homeLineup", "awayLineup", "teamStats", "penalties"):
        if not nuevos.get(campo) and previos.get(campo):
            nuevos[campo] = previos[campo]
    # Los sucesos sí se pisan con los frescos —el VAR anula goles y la lista
    # tiene que poder encoger—, salvo que ESPN no mande ninguno.
    if not nuevos.get("events") and previos.get("events"):
        nuevos["events"] = previos["events"]
    return nuevos


# ── Tablas derivadas ─────────────────────────────────────────────────────────

def construir_goleadores(match_days: list[dict]) -> tuple[list[dict], list[dict]]:
    """Goleadores y asistentes, a partir de los sucesos ya parseados.

    No cuesta ninguna petición y queda siempre coherente con lo que la app
    enseña en cada ficha. Los goles en propia meta no se le apuntan a nadie,
    que es el criterio de UEFA.
    """
    goles: dict[str, dict] = {}
    asistencias: dict[str, dict] = {}

    for dia in match_days:
        for partido in dia.get("games", []):
            for ev in ((partido.get("details") or {}).get("events") or []):
                equipo = ev.get("teamName")
                if ev.get("type") in ("GOAL", "PENALTY"):
                    autor = (ev.get("playerName") or "").strip()
                    if autor:
                        e = goles.setdefault(autor, {"goals": 0, "penalties": 0, "team": equipo})
                        e["goals"] += 1
                        if ev["type"] == "PENALTY":
                            e["penalties"] += 1
                        e["team"] = e["team"] or equipo
                    pasador = (ev.get("relatedPlayer") or "").strip()
                    if pasador:
                        a = asistencias.setdefault(pasador, {"goals": 0, "team": equipo})
                        a["goals"] += 1
                        a["team"] = a["team"] or equipo

    def ordenar(tabla: dict, con_penaltis: bool) -> list[dict]:
        filas = [
            {
                "player": jugador,
                "team": datos.get("team") or "",
                "goals": datos["goals"],
                **({"penalties": datos.get("penalties", 0)} if con_penaltis else {}),
                "athleteID": None,
            }
            for jugador, datos in tabla.items()
        ]
        filas.sort(key=lambda f: (-f["goals"], f["player"]))
        return filas[:40]

    return ordenar(goles, True), ordenar(asistencias, False)


def calcular_globales(match_days: list[dict]) -> int:
    """Rellena `aggregate` y `shootout` de las eliminatorias ya cerradas.

    El global se calcula sobre la vuelta y se guarda en los dos partidos del
    cruce, para que la app pueda enseñarlo abra el que abra.
    """
    por_cruce: dict[str, list[dict]] = {}
    for dia in match_days:
        for partido in dia.get("games", []):
            if partido.get("stage") in FASES_ELIMINATORIA and partido.get("tieId"):
                por_cruce.setdefault(partido["tieId"], []).append(partido)

    tocados = 0
    for partidos in por_cruce.values():
        if len(partidos) != 2 or not all(p.get("done") for p in partidos):
            continue
        ida, vuelta = sorted(partidos, key=lambda p: (p.get("leg") or 1))

        # Se acumula en el orden de la IDA: el local de la ida es el que la app
        # enseña a la izquierda del global.
        casa = fuera = 0
        valido = True
        for p in (ida, vuelta):
            marcador = (p.get("result") or "").split("-")
            if len(marcador) != 2 or not all(x.strip().isdigit() for x in marcador):
                valido = False
                break
            l, v = int(marcador[0]), int(marcador[1])
            if p["home"] == ida["home"]:
                casa += l; fuera += v
            else:
                casa += v; fuera += l
        if not valido:
            continue

        global_txt = f"{casa}-{fuera}"
        for p in (ida, vuelta):
            if p.get("aggregate") != global_txt:
                p["aggregate"] = global_txt
                tocados += 1
    return tocados


def descargar_clasificacion() -> list[dict]:
    """Tabla única de la fase liga."""
    datos = pedir(ESPN_STANDINGS, {"season": SEASON_YEAR})
    if not datos:
        return []
    grupos = datos.get("children") or []
    if not grupos:
        return []

    filas = []
    for e in (grupos[0].get("standings") or {}).get("entries") or []:
        stats = {s.get("name"): s for s in e.get("stats", [])}

        def valor(nombre: str) -> int:
            crudo = (stats.get(nombre) or {}).get("value")
            return int(crudo) if crudo is not None else 0

        filas.append({
            "team": normalizar_equipo((e.get("team") or {}).get("displayName")),
            "played": valor("gamesPlayed"),
            "won": valor("wins"),
            "drawn": valor("ties"),
            "lost": valor("losses"),
            "goalsFor": valor("pointsFor"),
            "goalsAgainst": valor("pointsAgainst"),
        })

    # ESPN deja el `rank` a 1 para todos antes del primer partido, así que se
    # ordena aquí y la tabla es coherente desde el día cero.
    filas.sort(key=lambda f: (-(f["won"] * 3 + f["drawn"]),
                              -(f["goalsFor"] - f["goalsAgainst"]),
                              -f["goalsFor"], f["team"]))
    for n, fila in enumerate(filas, start=1):
        fila["position"] = n
    return filas


# ── Entrada y salida ─────────────────────────────────────────────────────────

def cargar() -> dict:
    if not os.path.exists(DATA_FILE):
        sys.exit(f"ERROR: no existe {DATA_FILE}. "
                 "Genéralo primero con scripts/fetch_season.py")
    with open(DATA_FILE, encoding="utf-8") as f:
        return json.load(f)


def guardar(datos: dict) -> None:
    datos["lastUpdated"] = ahora_utc().strftime("%Y-%m-%dT%H:%M:%SZ")
    os.makedirs(os.path.dirname(os.path.abspath(DATA_FILE)), exist_ok=True)
    temporal = DATA_FILE + ".tmp"
    with open(temporal, "w", encoding="utf-8") as f:
        json.dump(datos, f, indent=2, ensure_ascii=False)
        f.write("\n")
    # Escritura atómica: el NAS sirve este mismo fichero y nadie debe leerlo a
    # medias.
    os.replace(temporal, DATA_FILE)


# ── Proceso principal ────────────────────────────────────────────────────────

def main() -> int:
    datos = cargar()

    # Índice por id de ESPN. Es estable entre pasadas, así que no hace falta
    # cruzar por fecha y equipos como en la app de La Liga.
    previos: dict[str, tuple[str, dict]] = {}
    for dia in datos.get("matchDays", []):
        for partido in dia.get("games", []):
            if partido.get("id"):
                previos[partido["id"]] = (dia["date"], partido)

    ventanas = ventanas_de_fase()
    hoy = ahora_utc()
    fechas = [(hoy + timedelta(days=d)).strftime("%Y%m%d")
              for d in range(-DIAS_ATRAS, DIAS_ADELANTE)]

    print(f"Consultando ESPN, {fechas[0]}–{fechas[-1]}")
    board = pedir(ESPN_SCOREBOARD,
                  {"dates": f"{fechas[0]}-{fechas[-1]}", "limit": 400})
    eventos = (board or {}).get("events", []) or []
    print(f"  {len(eventos)} partidos en la ventana")

    activos: list[str] = []
    actualizados: dict[str, dict] = {}

    for evento in eventos:
        if partido_activo(evento, hoy):
            activos.append(evento.get("name") or evento.get("id"))

        previo_par = previos.get(str(evento.get("id") or ""))
        previo = previo_par[1] if previo_par else None

        try:
            resultado = parsear_partido(evento, ventanas, previo)
        except Exception as e:      # un evento ilegible no puede tumbar la pasada
            print(f"  ⚠️  evento ilegible ({evento.get('id')}): {e}")
            continue
        if not resultado:
            continue
        partido, fecha = resultado

        # Ya cerrado y con detalles: no se vuelve a pedir el resumen.
        if previo and previo.get("done") and previo.get("details") and not FORCE_REFRESH:
            partido["details"] = previo["details"]
            partido["shootout"] = previo.get("shootout")
            actualizados[partido["id"]] = partido
            continue

        en_juego = partido.get("state") == "in"
        if (partido["done"] or en_juego) and partido["id"]:
            etiqueta = "en directo" if en_juego else "final"
            print(f"  · {partido['home']} {partido['result'] or ''} {partido['away']} ({etiqueta})")
            resumen = pedir(ESPN_SUMMARY, {"event": partido["id"]})
            frescos = None
            try:
                frescos = parsear_detalles(resumen, partido["home"], partido["away"])
            except Exception as e:
                print(f"    ⚠️  detalles no parseables: {e}")
            partido["details"] = fusionar_detalles(frescos, previo.get("details") if previo else None)
            partido["shootout"] = marcador_penaltis(
                (partido["details"] or {}).get("penalties"), partido["home"], partido["away"]
            )

        actualizados[partido["id"]] = partido

    # Reconstruir el calendario conservando todo lo que está fuera de la ventana.
    dias_nuevos: dict[str, list[dict]] = {}
    for dia in datos.get("matchDays", []):
        for partido in dia.get("games", []):
            fresco = actualizados.pop(partido.get("id", ""), None)
            dias_nuevos.setdefault(dia["date"], []).append(fresco or partido)
    # Partidos que ESPN publica y todavía no estaban (una eliminatoria recién
    # sorteada, por ejemplo).
    for partido in actualizados.values():
        evento = next((e for e in eventos if str(e.get("id")) == partido["id"]), None)
        fecha = fecha_hora_madrid(evento.get("date"))[0] if evento else None
        if fecha:
            dias_nuevos.setdefault(fecha, []).append(partido)
            print(f"  + nuevo en el calendario: {partido['home']} vs {partido['away']} ({fecha})")

    match_days = []
    for fecha in sorted(dias_nuevos):
        partidos = sorted(dias_nuevos[fecha], key=lambda g: (g.get("time") or "", g.get("home") or ""))
        match_days.append({
            "date": fecha,
            "matchday": partidos[0].get("matchday"),
            "stage": partidos[0].get("stage", "league"),
            "games": partidos,
        })

    globales = calcular_globales(match_days)
    if globales:
        print(f"  {globales} partidos con el global de la eliminatoria puesto al día")

    goleadores, asistentes = construir_goleadores(match_days)
    clasificacion = descargar_clasificacion()

    datos["matchDays"] = match_days
    datos["topScorers"] = goleadores
    datos["topAssists"] = asistentes
    if clasificacion:
        datos["standings"] = clasificacion

    escribir_bandera(bool(activos))
    if activos:
        print(f"En juego o a punto de empezar ({len(activos)}): {', '.join(activos[:6])}")
    else:
        print("Sin partidos activos")

    guardar(datos)
    print(f"✅ {DATA_FILE} · {len(match_days)} fechas · "
          f"{sum(len(d['games']) for d in match_days)} partidos · "
          f"{len(goleadores)} goleadores · {len(clasificacion)} en la tabla")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
