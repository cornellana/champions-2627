#!/usr/bin/env python3
"""
fetch_season.py

Construye desde cero `data/champions2627.json` con el calendario completo de la
UEFA Champions League que publica la API pública de ESPN (sin clave ni cuota).

Se ejecuta una vez al arrancar el proyecto y cada vez que UEFA sortea una fase
nueva: el script vuelve a leer el calendario entero y **preserva** lo que ya
había curado a mano (canal de TV) y lo que costó traer (alineaciones y eventos
de partidos ya jugados).

    python3 scripts/fetch_season.py

La forma del JSON es la misma que usa la app de La Liga, con tres campos más
que la Champions necesita: `stage`, `tieId` y `leg`.
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo

import requests

# -- Configuración --------------------------------------------------------

ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports/soccer/uefa.champions"
ESPN_STANDINGS = "https://site.api.espn.com/apis/v2/sports/soccer/uefa.champions/standings"
SEASON_YEAR = 2026
SEASON_LABEL = "2026-27"
JSON_PATH = Path("data/champions2627.json")
MADRID = ZoneInfo("Europe/Madrid")
TIMEOUT = 30

# Ventanas mensuales que se barren para localizar todos los partidos. Cubren de
# julio a junio para no dejar fuera ni la previa ni la final.
MONTH_RANGES = [
    "20260701-20260731", "20260801-20260831", "20260901-20260930",
    "20261001-20261031", "20261101-20261130", "20261201-20261231",
    "20270101-20270131", "20270201-20270228", "20270301-20270331",
    "20270401-20270430", "20270501-20270531", "20270601-20270630",
]

# -- Nombres de club: ESPN (inglés) → nombre canónico de la app -----------
#
# El nombre canónico es la clave con la que viajan los datos y con la que la app
# busca la traducción a catalán, castellano e inglés (ver `Teams.swift`). Aquí
# solo se normaliza lo que ESPN escribe de forma distinta a como se conoce el
# club, o lo que en castellano tiene forma propia asentada.

TEAM_NAME_MAP: dict[str, str] = {
    "AEK Athens": "AEK Atenas",
    "AS Roma": "Roma",
    "Arsenal": "Arsenal",
    "Aston Villa": "Aston Villa",
    "Atletico Madrid": "Atlético de Madrid",
    "Atlético Madrid": "Atlético de Madrid",
    "Atlético de Madrid": "Atlético de Madrid",
    "Barcelona": "FC Barcelona",
    "Bayern Munich": "Bayern de Múnich",
    "Bayern München": "Bayern de Múnich",
    "Bodo/Glimt": "Bodø/Glimt",
    "Bodø/Glimt": "Bodø/Glimt",
    "Borussia Dortmund": "Borussia Dortmund",
    "Club Brugge": "Brujas",
    "Club Brugge KV": "Brujas",
    "Como": "Como",
    "FC Porto": "Oporto",
    "Porto": "Oporto",
    "Fenerbahce": "Fenerbahçe",
    "Fenerbahçe": "Fenerbahçe",
    "Feyenoord Rotterdam": "Feyenoord",
    "Feyenoord": "Feyenoord",
    "Galatasaray": "Galatasaray",
    "Internazionale": "Inter de Milán",
    "Inter Milan": "Inter de Milán",
    "LASK Linz": "LASK",
    "Lens": "Lens",
    "Lille": "Lille",
    "Liverpool": "Liverpool",
    "Manchester City": "Manchester City",
    "Manchester United": "Manchester United",
    "Napoli": "Nápoles",
    "PSV Eindhoven": "PSV",
    "Paris Saint-Germain": "Paris Saint-Germain",
    "RB Leipzig": "RB Leipzig",
    "Real Betis": "Real Betis",
    "Real Madrid": "Real Madrid",
    "Sabah FK": "Sabah",
    "Shakhtar Donetsk": "Shajtar Donetsk",
    "Slavia Prague": "Slavia de Praga",
    "Slovan Bratislava": "Slovan Bratislava",
    "Sporting CP": "Sporting de Portugal",
    "VfB Stuttgart": "Stuttgart",
    "Viking FK": "Viking",
    "Villarreal": "Villarreal",
}

# -- Ciudades: ESPN (inglés) → castellano ---------------------------------

CITY_MAP: dict[str, str] = {
    "Athens": "Atenas", "London": "Londres", "Munich": "Múnich",
    "Milan": "Milán", "Milano": "Milán", "Rome": "Roma", "Roma": "Roma",
    "Naples": "Nápoles", "Napoli": "Nápoles", "Lisbon": "Lisboa",
    "Prague": "Praga", "Vienna": "Viena", "Warsaw": "Varsovia",
    "Copenhagen": "Copenhague", "Brussels": "Bruselas", "Bruges": "Brujas",
    "Antwerp": "Amberes", "The Hague": "La Haya", "Turin": "Turín",
    "Seville": "Sevilla", "Genoa": "Génova", "Florence": "Florencia",
    "Istanbul": "Estambul", "Moscow": "Moscú", "Kyiv": "Kiev",
    "Bucharest": "Bucarest", "Belgrade": "Belgrado", "Zagreb": "Zagreb",
    "Salzburg": "Salzburgo", "Zurich": "Zúrich", "Geneva": "Ginebra",
    "Gothenburg": "Gotemburgo", "Nicosia": "Nicosia", "Baku": "Bakú",
    "Porto": "Oporto", "Oporto": "Oporto", "Dortmund": "Dortmund",
}

# -- Fases: id del `seasontype` de ESPN → clave interna -------------------
#
# ESPN identifica cada fase con un `type` numérico dentro del `calendar` del
# scoreboard. Las etiquetas cambian de idioma según el locale, así que se
# reconocen por el texto en inglés, que es el que devuelve por defecto.

STAGE_BY_LABEL: dict[str, str] = {
    "league phase": "league",
    "knockout round playoffs": "playoff",
    "rd of 16": "r16",
    "round of 16": "r16",
    "quarterfinals": "qf",
    "semifinals": "sf",
    "final": "final",
}

# Fases eliminatorias en orden, para ordenar el cuadro.
KNOCKOUT_ORDER = ["playoff", "r16", "qf", "sf", "final"]


# -- Cliente HTTP ---------------------------------------------------------

def espn_get(url: str, params: dict | None = None) -> dict:
    r = requests.get(url, params=params, timeout=TIMEOUT)
    r.raise_for_status()
    return r.json()


# -- Utilidades -----------------------------------------------------------

def madrid_datetime(utc_iso: str) -> datetime:
    """Convierte el timestamp UTC de ESPN a hora local de Madrid."""
    dt = datetime.fromisoformat(utc_iso.replace("Z", "+00:00"))
    return dt.astimezone(MADRID)


def normalize_team(espn_name: str | None) -> str:
    if not espn_name:
        return "?"
    return TEAM_NAME_MAP.get(espn_name.strip(), espn_name.strip())


def normalize_city(venue: dict | None) -> str | None:
    if not venue:
        return None
    city = ((venue.get("address") or {}).get("city") or "").strip()
    if not city:
        return None
    return CITY_MAP.get(city, city)


def stage_windows() -> list[tuple[str, datetime, datetime]]:
    """Lee del propio scoreboard las ventanas de fecha de cada fase.

    Devuelve una lista de (clave_de_fase, inicio, fin) en UTC. Así la app sabe
    en qué fase está sin que nadie codifique las fechas a mano, y el día que
    UEFA mueva una eliminatoria el script se entera solo.
    """
    board = espn_get(f"{ESPN_BASE}/scoreboard")
    calendars = (board.get("leagues") or [{}])[0].get("calendar") or []
    entries = []
    for block in calendars:
        for entry in block.get("entries", []) or []:
            label = (entry.get("label") or "").strip().lower()
            stage = STAGE_BY_LABEL.get(label)
            if not stage:
                continue
            entries.append((
                stage,
                datetime.fromisoformat(entry["startDate"].replace("Z", "+00:00")),
                datetime.fromisoformat(entry["endDate"].replace("Z", "+00:00")),
            ))
    if not entries:
        sys.exit("ERROR: ESPN no devolvió el calendario de fases.")
    return entries


def stage_for(utc_iso: str, windows: list[tuple[str, datetime, datetime]]) -> str:
    dt = datetime.fromisoformat(utc_iso.replace("Z", "+00:00"))
    for stage, start, end in windows:
        if start <= dt <= end:
            return stage
    # Fuera de toda ventana conocida: casi siempre la final, que ESPN a veces
    # deja con la ventana de semifinales abierta hasta junio.
    return "final"


# -- Descarga del calendario ---------------------------------------------

def fetch_all_events() -> list[dict]:
    """Barre el año entero y devuelve los eventos sin repetir."""
    seen: set[str] = set()
    events: list[dict] = []
    for rng in MONTH_RANGES:
        try:
            board = espn_get(f"{ESPN_BASE}/scoreboard",
                             {"dates": rng, "limit": 400})
        except requests.HTTPError as exc:
            print(f"  ⚠️  {rng}: {exc}", file=sys.stderr)
            continue
        for ev in board.get("events", []) or []:
            if ev["id"] in seen:
                continue
            seen.add(ev["id"])
            events.append(ev)
        print(f"  {rng}: {len(board.get('events') or [])} partidos")
    return events


# -- Jornadas de la fase liga --------------------------------------------

def assign_matchdays(league_dates: list[str]) -> dict[str, int]:
    """Agrupa las fechas de la fase liga en las ocho jornadas.

    ESPN no publica el número de jornada (`week` viene vacío), pero el
    calendario lo dice solo: cada jornada ocupa días consecutivos y entre una y
    la siguiente pasan semanas. Se agrupan las fechas cuya distancia sea de dos
    días o menos.
    """
    ordered = sorted(set(league_dates))
    if not ordered:
        return {}

    grupos: list[list[str]] = [[ordered[0]]]
    for fecha in ordered[1:]:
        anterior = datetime.strptime(grupos[-1][-1], "%Y-%m-%d")
        actual = datetime.strptime(fecha, "%Y-%m-%d")
        if (actual - anterior).days <= 2:
            grupos[-1].append(fecha)
        else:
            grupos.append([fecha])

    return {fecha: n for n, grupo in enumerate(grupos, start=1) for fecha in grupo}


# -- Eliminatorias: emparejar ida y vuelta -------------------------------

def assign_ties(games: list[dict]) -> None:
    """Marca `tieId` y `leg` en los partidos de eliminatoria.

    Dos partidos son la misma eliminatoria cuando enfrentan a los mismos dos
    equipos dentro de la misma fase. La ida es el que se juega antes. La final,
    a partido único, se queda sin `tieId`.
    """
    por_fase: dict[str, list[dict]] = {}
    for g in games:
        if g["stage"] in ("league", "final"):
            continue
        por_fase.setdefault(g["stage"], []).append(g)

    for stage, partidos in por_fase.items():
        parejas: dict[frozenset[str], list[dict]] = {}
        for g in partidos:
            parejas.setdefault(frozenset({g["home"], g["away"]}), []).append(g)

        for n, (_, dos) in enumerate(sorted(
                parejas.items(), key=lambda kv: min(g["_utc"] for g in kv[1])), start=1):
            dos.sort(key=lambda g: g["_utc"])
            tie_id = f"{stage}-{n}"
            for leg, g in enumerate(dos, start=1):
                g["tieId"] = tie_id
                g["leg"] = leg if len(dos) > 1 else None


# -- Construcción de cada partido ----------------------------------------

def build_game(event: dict, windows) -> dict | None:
    comp = (event.get("competitions") or [{}])[0]
    competitors = comp.get("competitors") or []
    if len(competitors) < 2:
        return None

    home = away = None
    home_score = away_score = None
    for c in competitors:
        name = normalize_team((c.get("team") or {}).get("displayName"))
        score = c.get("score")
        if c.get("homeAway") == "home":
            home, home_score = name, score
        else:
            away, away_score = name, score
    if not home or not away:
        return None

    utc = event.get("date") or ""
    local = madrid_datetime(utc)
    status = (event.get("status") or {}).get("type") or {}
    completed = bool(status.get("completed"))

    result = None
    if completed and home_score is not None and away_score is not None:
        result = f"{home_score}-{away_score}"

    venue = comp.get("venue") or {}

    return {
        "id": str(event.get("id")),
        "_utc": utc,                       # interno: se borra antes de guardar
        "date": local.strftime("%Y-%m-%d"),
        "time": local.strftime("%H:%M"),
        "home": home,
        "away": away,
        "stage": stage_for(utc, windows),
        "matchday": None,
        "tieId": None,
        "leg": None,
        "tv": None,                        # se cura a mano: ESPN solo da EE.UU.
        "done": completed,
        "result": result,
        "aggregate": None,
        "shootout": None,
        "state": status.get("state"),
        "clock": None,
        "statusText": status.get("description"),
        "stadium": (venue.get("fullName") or "").strip() or None,
        "venueCity": normalize_city(venue),
        "details": None,
    }


# -- Clasificación --------------------------------------------------------

def fetch_standings() -> list[dict]:
    """Tabla única de 36 equipos de la fase liga."""
    try:
        data = espn_get(ESPN_STANDINGS, {"season": SEASON_YEAR})
    except requests.HTTPError as exc:
        print(f"  ⚠️  clasificación no disponible: {exc}", file=sys.stderr)
        return []

    grupos = data.get("children") or []
    if not grupos:
        return []
    entries = (grupos[0].get("standings") or {}).get("entries") or []

    filas = []
    for e in entries:
        stats = {s.get("name"): s for s in e.get("stats", [])}

        def val(name: str) -> int:
            raw = (stats.get(name) or {}).get("value")
            return int(raw) if raw is not None else 0

        filas.append({
            "team": normalize_team((e.get("team") or {}).get("displayName")),
            "played": val("gamesPlayed"),
            "won": val("wins"),
            "drawn": val("ties"),
            "lost": val("losses"),
            "goalsFor": val("pointsFor"),
            "goalsAgainst": val("pointsAgainst"),
            "points": val("points"),
        })

    # ESPN da `rank`, pero antes del primer partido lo deja todo a 1. Se ordena
    # aquí para tener siempre una tabla coherente.
    filas.sort(key=lambda f: (
        -f["points"],
        -(f["goalsFor"] - f["goalsAgainst"]),
        -f["goalsFor"],
        f["team"],
    ))
    for n, fila in enumerate(filas, start=1):
        fila["position"] = n
    return filas


# -- Preservar lo curado --------------------------------------------------

def merge_previous(games: list[dict], anterior: dict | None) -> None:
    """Conserva del fichero anterior lo que el script no sabe regenerar.

    - `tv`: se cura a mano, ESPN no lo da para España.
    - `details`, `aggregate`, `shootout`: cuestan una petición por partido y
      solo los trae `update_champions.py`; rehacerlos aquí sería tirar trabajo.
    """
    if not anterior:
        return
    previos: dict[str, dict] = {}
    for day in anterior.get("matchDays", []):
        for g in day.get("games", []):
            previos[g["id"]] = g

    conservados = 0
    for g in games:
        old = previos.get(g["id"])
        if not old:
            continue
        for campo in ("tv", "details", "aggregate", "shootout"):
            if old.get(campo) is not None:
                g[campo] = old[campo]
        # Un partido ya cerrado no vuelve atrás aunque ESPN tenga un mal día.
        if old.get("done") and not g["done"]:
            g["done"] = True
            g["result"] = old.get("result")
            g["state"] = "post"
        if old.get("details"):
            conservados += 1
    if conservados:
        print(f"  Detalles conservados de la versión anterior: {conservados}")


# -- Orquestación ---------------------------------------------------------

def main() -> int:
    print(f"Calendario de la Champions {SEASON_LABEL} desde ESPN\n")

    windows = stage_windows()
    print("Fases publicadas:")
    for stage, start, end in windows:
        print(f"  {stage:<8} {start:%d/%m/%Y} → {end:%d/%m/%Y}")
    print()

    print("Descargando partidos:")
    events = fetch_all_events()
    print(f"\nTotal de eventos: {len(events)}")

    games = [g for g in (build_game(e, windows) for e in events) if g]
    print(f"Partidos válidos: {len(games)}")

    # Jornada de la fase liga
    matchdays = assign_matchdays([g["date"] for g in games if g["stage"] == "league"])
    for g in games:
        if g["stage"] == "league":
            g["matchday"] = matchdays.get(g["date"])

    # Ida y vuelta de las eliminatorias
    assign_ties(games)

    # Resumen por fase
    print("\nReparto por fase:")
    for stage in ["league"] + KNOCKOUT_ORDER:
        n = sum(1 for g in games if g["stage"] == stage)
        if n:
            print(f"  {stage:<8} {n:>3} partidos")
    if matchdays:
        print("\nJornadas de la fase liga:")
        for jornada in sorted(set(matchdays.values())):
            fechas = sorted(f for f, j in matchdays.items() if j == jornada)
            n = sum(1 for g in games if g.get("matchday") == jornada)
            print(f"  J{jornada}: {n:>2} partidos · {', '.join(fechas)}")

    anterior = None
    if JSON_PATH.exists():
        anterior = json.loads(JSON_PATH.read_text(encoding="utf-8"))
    merge_previous(games, anterior)

    # Agrupar por fecha
    por_fecha: dict[str, list[dict]] = {}
    for g in games:
        por_fecha.setdefault(g["date"], []).append(g)

    match_days = []
    for fecha in sorted(por_fecha):
        del_dia = sorted(por_fecha[fecha], key=lambda g: (g["time"], g["home"]))
        stage = del_dia[0]["stage"]
        for g in del_dia:
            g.pop("_utc", None)
            g.pop("date", None)
        match_days.append({
            "date": fecha,
            "matchday": del_dia[0].get("matchday"),
            "stage": stage,
            "games": del_dia,
        })

    print("\nClasificación:")
    standings = fetch_standings()
    print(f"  {len(standings)} equipos")

    snapshot = {
        "lastUpdated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "season": SEASON_LABEL,
        "competition": "UEFA Champions League",
        "matchDays": match_days,
        "standings": standings,
        "topScorers": (anterior or {}).get("topScorers", []),
        "topAssists": (anterior or {}).get("topAssists", []),
    }

    JSON_PATH.parent.mkdir(parents=True, exist_ok=True)
    JSON_PATH.write_text(
        json.dumps(snapshot, indent=2, ensure_ascii=False, sort_keys=False) + "\n",
        encoding="utf-8",
    )
    tam = JSON_PATH.stat().st_size / 1024
    print(f"\n✅ {JSON_PATH} — {len(match_days)} fechas, {len(games)} partidos, {tam:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
