#!/usr/bin/env python3
"""
build_strings.py

Genera `Champions/Localizable.xcstrings` —el catálogo de idiomas de Xcode— a
partir de la tabla de abajo, en la que cada clave lleva sus tres traducciones
una al lado de la otra.

Se hace así porque el formato del catálogo es JSON anidado y muy verboso: tener
las tres lenguas en la misma línea es la única forma de revisar de un vistazo
que ninguna se ha quedado sin traducir o dice algo distinto de las otras.

    python3 scripts/build_strings.py

Xcode puede seguir editando el `.xcstrings` después; volver a ejecutar el script
sobrescribe el fichero, así que si se traduce desde Xcode conviene traer el
cambio también aquí.
"""

from __future__ import annotations

import json
from pathlib import Path

DESTINO = Path("Champions/Localizable.xcstrings")

# clave: (inglés, castellano, catalán)
STRINGS: dict[str, tuple[str, str, str]] = {

    # -- Identidad ---------------------------------------------------------
    "app.title":       ("Champions League", "Champions League", "Champions League"),
    # En la barra superior el nombre entero no cabe y se corta a la mitad.
    "app.title.short": ("Champions", "Champions", "Champions"),

    "app.season":      ("Season %@", "Temporada %@", "Temporada %@"),

    # -- Pronóstico --------------------------------------------------------
    "prediction.title":         ("Forecast", "Pronóstico", "Pronòstic"),
    "prediction.form":          ("Recent form", "Forma reciente", "Forma recent"),
    "prediction.goalsFor":      ("Goals for /match", "Goles a favor /p", "Gols a favor /p"),
    "prediction.goalsAgainst":  ("Goals against /match", "Goles en contra /p", "Gols en contra /p"),
    "prediction.position":      ("Position", "Puesto", "Posició"),
    "prediction.expectedGoals": ("Expected goals", "Goles esperados", "Gols esperats"),
    "prediction.basis": (
        "Statistical estimate from the results so far in the competition.",
        "Estimación estadística a partir de los resultados que lleva la competición.",
        "Estimació estadística a partir dels resultats que porta la competició."),
    "prediction.baseline": (
        "No matches played yet: this is only the home advantage. It sharpens as results come in.",
        "Todavía no se ha jugado nada: esto es solo la ventaja de jugar en casa. Se afina conforme lleguen resultados.",
        "Encara no s'ha jugat res: això és només l'avantatge de jugar a casa. S'afina a mesura que arribin resultats."),

    # -- Plantillas --------------------------------------------------------
    "roster.title":       ("Squads", "Plantillas", "Plantilles"),
    "roster.loading":     ("Loading squads…", "Cargando plantillas…", "Carregant plantilles…"),
    "roster.unavailable": ("Squads not available for this match",
                           "No hay plantillas disponibles de este partido",
                           "No hi ha plantilles disponibles d'aquest partit"),
    "roster.noneForTeam": ("Not available", "No disponible", "No disponible"),

    "position.goalkeepers":  ("Goalkeepers", "Porteros", "Porters"),
    "position.defenders":    ("Defenders", "Defensas", "Defenses"),
    "position.midfielders":  ("Midfielders", "Centrocampistas", "Migcampistes"),
    "position.forwards":     ("Forwards", "Delanteros", "Davanters"),
    "position.others":       ("Others", "Otros", "Altres"),

    # -- Calendario por equipo ---------------------------------------------
    "calendar.title":      ("Calendar", "Calendario", "Calendari"),
    "venue.home.initial":  ("H", "L", "L"),
    "venue.away.initial":  ("A", "V", "V"),
    "a11y.calendar":       ("Calendar", "Calendario", "Calendari"),

    "action.cancel": ("Cancel", "Cancelar", "Cancel·lar"),
    "action.add":    ("Add", "Añadir", "Afegir"),

    "settings.team":           ("Team", "Equipo", "Equip"),
    "settings.highlightColor": ("Highlight colour", "Color de resaltado", "Color de ressaltat"),
    "settings.preview.rival":  ("Opponent", "Equipo rival", "Equip rival"),
    "settings.notifications.openSettings": ("Turn on in iOS Settings",
                                            "Activar en los Ajustes de iOS",
                                            "Activar a la Configuració d'iOS"),

    # -- Idioma ------------------------------------------------------------
    "settings.language":         ("Language", "Idioma", "Idioma"),
    # Cada idioma se escribe en su propia lengua: se reconoce de un vistazo
    # aunque la app esté ahora mismo en un idioma que no entiendes.
    "language.system":           ("Phone language", "El del teléfono", "El del telèfon"),
    "language.catalan":          ("Català", "Català", "Català"),
    "language.spanish":          ("Castellano", "Castellano", "Castellano"),
    "language.english":          ("English", "English", "English"),
    "settings.language.restart": ("Reopen the app to see the change",
                                  "Vuelve a abrir la app para verlo",
                                  "Torna a obrir l'app per veure-ho"),
    "settings.language.help": (
        "iOS resolves the language when the app launches, so the change shows up the next time you open it.",
        "iOS resuelve el idioma al arrancar la app, así que el cambio se ve la próxima vez que la abras.",
        "iOS resol l'idioma en arrencar l'app, així que el canvi es veu el pròxim cop que l'obris."),

    # -- Fases -------------------------------------------------------------
    "stage.league":  ("League Phase", "Fase liga", "Fase lliga"),
    "stage.playoff": ("Knockout Play-off", "Play-off", "Play-off"),
    "stage.r16":     ("Round of 16", "Octavos de final", "Vuitens de final"),
    "stage.qf":      ("Quarter-finals", "Cuartos de final", "Quarts de final"),
    "stage.sf":      ("Semi-finals", "Semifinales", "Semifinals"),
    "stage.final":   ("Final", "Final", "Final"),

    "stage.league.short":  ("League", "Liga", "Lliga"),
    "stage.playoff.short": ("Play-off", "Play-off", "Play-off"),
    "stage.r16.short":     ("R16", "Octavos", "Vuitens"),
    "stage.qf.short":      ("QF", "Cuartos", "Quarts"),
    "stage.sf.short":      ("SF", "Semis", "Semis"),
    "stage.final.short":   ("Final", "Final", "Final"),

    # -- Jornadas ----------------------------------------------------------
    "matchday.short": ("MD%d", "J%d", "J%d"),
    "matchday.long":  ("Matchday %d", "Jornada %d", "Jornada %d"),

    # -- Ida y vuelta ------------------------------------------------------
    "leg.first":       ("1st", "Ida", "Anada"),
    "leg.second":      ("2nd", "Vuelta", "Tornada"),
    "leg.first.long":  ("First leg", "Partido de ida", "Partit d'anada"),
    "leg.second.long": ("Second leg", "Partido de vuelta", "Partit de tornada"),
    "leg.single":      ("Single", "Único", "Únic"),

    # -- Estado del partido ------------------------------------------------
    "match.final":    ("Full time", "Final", "Final"),
    "match.live":     ("LIVE", "EN JUEGO", "EN JOC"),
    "match.halftime": ("Half time", "Descanso", "Descans"),
    "match.delayed":  ("Delayed", "Aplazado", "Ajornat"),

    # -- Sucesos -----------------------------------------------------------
    "event.goal":          ("Goal", "Gol", "Gol"),
    "event.ownGoal":       ("Own goal", "Gol en propia", "Gol en pròpia"),
    "event.penalty":       ("Penalty", "Penalti", "Penal"),
    "event.missedPenalty": ("Penalty missed", "Penalti fallado", "Penal fallat"),
    "event.yellowCard":    ("Yellow card", "Tarjeta amarilla", "Targeta groga"),
    "event.redCard":       ("Red card", "Tarjeta roja", "Targeta vermella"),
    "event.substitution":  ("Substitution", "Cambio", "Canvi"),

    # -- Zonas de la clasificación ----------------------------------------
    "zone.direct":  ("Straight to the round of 16", "Octavos directos", "Vuitens directes"),
    "zone.playoff": ("Knockout play-off", "Play-off de acceso", "Play-off d'accés"),
    "zone.out":     ("Eliminated", "Eliminados", "Eliminats"),

    # -- Filtros -----------------------------------------------------------
    "filter.team":      ("Team", "Equipo", "Equip"),
    "filter.allTeams":  ("All teams", "Todos los equipos", "Tots els equips"),
    "filter.stage":     ("Stage", "Fase", "Fase"),
    "filter.allStages": ("Whole tournament", "Todo el torneo", "Tot el torneig"),
    "filter.knockout":  ("Knockout", "Eliminatorias", "Eliminatòries"),

    # -- Estados de pantalla ----------------------------------------------
    "state.loading":       ("Loading…", "Cargando…", "Carregant…"),
    "state.empty.detail":  ("The fixtures will load on their own\nas soon as they are published",
                            "El calendario se cargará solo\nen cuanto esté publicado",
                            "El calendari es carregarà sol\nquan estigui publicat"),
    "state.pullToRefresh": ("Pull down to refresh", "Desliza hacia abajo para actualizar",
                            "Llisca cap avall per actualitzar"),

    "error.noConnection": ("No connection", "Sin conexión", "Sense connexió"),
    "error.offline":      ("Showing saved data", "Mostrando datos guardados",
                           "Mostrant dades desades"),

    # -- Origen de los datos ----------------------------------------------
    "source.live":   ("live", "en directo", "en directe"),
    "source.github": ("GitHub", "GitHub", "GitHub"),
    "source.seed":   ("offline", "sin conexión", "sense connexió"),

    # -- Acciones ----------------------------------------------------------
    "action.close": ("Close", "Cerrar", "Tancar"),
    "action.done":  ("Done", "Listo", "Fet"),

    # -- Clasificación -----------------------------------------------------
    "standings.title":            ("Standings", "Clasificación", "Classificació"),
    "standings.team":             ("Team", "Equipo", "Equip"),
    "standings.played.short":     ("P", "PJ", "PJ"),
    "standings.won.short":        ("W", "G", "G"),
    "standings.drawn.short":      ("D", "E", "E"),
    "standings.lost.short":       ("L", "P", "P"),
    "standings.goalDiff.short":   ("GD", "DG", "DG"),
    "standings.points.short":     ("Pts", "Pts", "Pts"),

    "form.win.initial":  ("W", "V", "V"),
    "form.draw.initial": ("D", "E", "E"),
    "form.loss.initial": ("L", "D", "D"),

    # -- Goleadores --------------------------------------------------------
    "scorers.title":     ("Top scorers", "Goleadores", "Golejadors"),
    "scorers.goals":     ("Goals", "Goles", "Gols"),
    "scorers.assists":   ("Assists", "Asistencias", "Assistències"),
    "scorers.penalties": ("%d pen.", "%d de penalti", "%d de penal"),
    "scorers.empty":     ("No one has scored yet in this competition",
                          "Todavía no ha marcado nadie en esta competición",
                          "Encara no ha marcat ningú en aquesta competició"),

    # -- Ficha del partido -------------------------------------------------
    "detail.summary":    ("Summary", "Resumen", "Resum"),
    "detail.lineups":    ("Line-ups", "Alineaciones", "Alineacions"),
    "detail.stats":      ("Stats", "Estadísticas", "Estadístiques"),
    "detail.section":    ("Section", "Sección", "Secció"),
    "detail.timeline":   ("Timeline", "Cronología", "Cronologia"),
    "detail.penalties":  ("Penalty shootout", "Tanda de penaltis", "Tanda de penals"),
    "detail.noEvents":   ("No events recorded for this match",
                          "No hay sucesos registrados de este partido",
                          "No hi ha esdeveniments registrats d'aquest partit"),
    "detail.notPlayed":  ("This match has not been played yet",
                          "Este partido todavía no se ha jugado",
                          "Aquest partit encara no s'ha jugat"),
    "detail.noStats":    ("No stats available", "No hay estadísticas disponibles",
                          "No hi ha estadístiques disponibles"),
    "detail.shootout":   ("%d-%d on penalties", "%d-%d en los penaltis", "%d-%d als penals"),
    "detail.aggregate":  ("%d-%d on aggregate", "%d-%d en el global", "%d-%d en el global"),

    "lineup.substitutes": ("Substitutes", "Suplentes", "Suplents"),

    # -- Cuadro ------------------------------------------------------------
    "bracket.title":     ("Knockout bracket", "Cuadro final", "Quadre final"),
    "bracket.pending":   ("Draw not made yet", "Pendiente de sorteo", "Pendent de sorteig"),
    "bracket.aggregate": ("AGGREGATE", "GLOBAL", "GLOBAL"),

    # -- Ajustes -----------------------------------------------------------
    "settings.title":       ("Settings", "Ajustes", "Configuració"),
    "settings.followed":    ("Teams you follow", "Equipos que sigues", "Equips que segueixes"),
    "settings.followed.help": (
        "Their matches are highlighted in the list, and they are the ones that send you alerts.",
        "Sus partidos se resaltan en la lista y son los que te mandan avisos.",
        "Els seus partits es ressalten a la llista i són els que t'envien avisos."),
    "settings.noTeams":     ("You are not following any team yet",
                             "Todavía no sigues a ningún equipo",
                             "Encara no segueixes cap equip"),
    "settings.addTeam":     ("Add a team", "Añadir equipo", "Afegir equip"),
    "settings.searchTeam":  ("Search team", "Buscar equipo", "Cercar equip"),

    "settings.notifications":           ("Alerts", "Avisos", "Avisos"),
    "settings.notifications.enabled":   ("Send me alerts", "Mandarme avisos", "Enviar-me avisos"),
    "settings.notifications.goals":     ("Goals", "Goles", "Gols"),
    "settings.notifications.penalties": ("Penalties", "Penaltis", "Penals"),
    "settings.notifications.redCards":  ("Red cards", "Tarjetas rojas", "Targetes vermelles"),
    "settings.notifications.startEnd":  ("Kick-off and full time", "Principio y final",
                                         "Inici i final"),
    "settings.notifications.kickoff":   ("Remind me before kick-off",
                                         "Recordármelo antes del saque",
                                         "Recordar-m'ho abans de la sortida"),
    "settings.notifications.kickoffMinutes": ("How early", "Antelación", "Antelació"),
    "settings.notifications.denied": (
        "Alerts are switched off in iOS Settings.",
        "Los avisos están desactivados en los Ajustes de iOS.",
        "Els avisos estan desactivats a la Configuració d'iOS."),
    "settings.notifications.help": (
        "Live alerts come from the updater at home; the kick-off reminder is set by this phone and works without it.",
        "Los avisos en vivo llegan del actualizador de casa; el recordatorio del saque lo programa este teléfono y funciona sin él.",
        "Els avisos en directe arriben de l'actualitzador de casa; el recordatori de la sortida el programa aquest telèfon i funciona sense ell."),
    "settings.minutes": ("%d min", "%d min", "%d min"),

    "settings.about":       ("About", "Acerca de", "Quant a"),
    "settings.season":      ("Season", "Temporada", "Temporada"),
    "settings.lastUpdate":  ("Last update", "Última actualización", "Última actualització"),
    "settings.source":      ("Source", "Origen", "Origen"),
    "settings.data.credit": ("Fixtures and results from ESPN's public data.",
                             "Calendario y resultados a partir de los datos públicos de ESPN.",
                             "Calendari i resultats a partir de les dades públiques d'ESPN."),

    # -- Recordatorio local ------------------------------------------------
    "reminder.title": ("Almost kick-off", "Está a punto de empezar", "Està a punt de començar"),
    "reminder.body":  ("%1$@ – %2$@ kicks off in %3$d minutes",
                       "%1$@ – %2$@ empieza en %3$d minutos",
                       "%1$@ – %2$@ comença d'aquí a %3$d minuts"),

    # -- Estadísticas de equipo -------------------------------------------
    # Las claves las escribe ESPN; el script solo publica estas, así que no
    # puede colarse ninguna sin traducir.
    "stat.possessionPct":  ("Possession", "Posesión", "Possessió"),
    "stat.totalShots":     ("Shots", "Tiros", "Xuts"),
    "stat.shotsOnTarget":  ("On target", "A puerta", "A porta"),
    "stat.wonCorners":     ("Corners", "Córners", "Córners"),
    "stat.foulsCommitted": ("Fouls", "Faltas", "Faltes"),
    "stat.offsides":       ("Offsides", "Fueras de juego", "Fores de joc"),
    "stat.yellowCards":    ("Yellow cards", "Amarillas", "Grogues"),
    "stat.redCards":       ("Red cards", "Rojas", "Vermelles"),
    "stat.saves":          ("Saves", "Paradas", "Aturades"),
    "stat.accuratePasses": ("Accurate passes", "Pases buenos", "Passades bones"),
    "stat.passPct":        ("Pass accuracy", "Acierto en el pase", "Encert en la passada"),

    # -- Accesibilidad -----------------------------------------------------
    "a11y.settings":  ("Settings", "Ajustes", "Configuració"),
    "a11y.bracket":   ("Knockout bracket", "Cuadro final", "Quadre final"),
    "a11y.scorers":   ("Top scorers", "Goleadores", "Golejadors"),
    "a11y.standings": ("Standings", "Clasificación", "Classificació"),
    "a11y.teamColor": ("Team colour", "Color del equipo", "Color de l'equip"),
}


def main() -> int:
    catalogo = {
        "sourceLanguage": "en",
        "version": "1.0",
        "strings": {
            clave: {
                "extractionState": "manual",
                "localizations": {
                    idioma: {"stringUnit": {"state": "translated", "value": texto}}
                    for idioma, texto in zip(("en", "es", "ca"), textos)
                },
            }
            for clave, textos in sorted(STRINGS.items())
        },
    }

    DESTINO.parent.mkdir(parents=True, exist_ok=True)
    DESTINO.write_text(
        json.dumps(catalogo, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    faltan = [c for c, t in STRINGS.items() if any(not x.strip() for x in t)]
    if faltan:
        print("⚠️  Claves sin traducir en algún idioma:")
        for c in faltan:
            print(f"   {c}")

    print(f"✅ {DESTINO} — {len(STRINGS)} claves × 3 idiomas (en · es · ca)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
