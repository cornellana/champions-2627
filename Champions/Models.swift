//
//  Models.swift
//  Champions
//
//  Modelos de dominio de la UEFA Champions League 2026-27.
//
//  La forma del JSON es la misma que usa la app de La Liga, con tres campos más
//  que este torneo necesita: `stage` (fase), `tieId` y `leg` (ida y vuelta de
//  las eliminatorias).
//

import Foundation
import SwiftUI

// MARK: - Stage

/// Fase del torneo a la que pertenece un partido.
///
/// El `rawValue` viaja en el JSON y lo escribe el script de actualización, así
/// que no debe cambiarse aunque cambie el texto que ve el usuario.
enum Stage: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Fase liga: 36 equipos, una sola tabla, ocho jornadas.
    case league
    /// Play-off de acceso a octavos (puestos 9 a 24).
    case playoff
    /// Octavos de final.
    case r16
    /// Cuartos de final.
    case qf
    /// Semifinales.
    case sf
    /// Final, a partido único en campo neutral.
    case final

    var id: String { rawValue }

    /// Orden natural dentro del torneo, para ordenar el cuadro.
    var order: Int {
        switch self {
        case .league:  return 0
        case .playoff: return 1
        case .r16:     return 2
        case .qf:      return 3
        case .sf:      return 4
        case .final:   return 5
        }
    }

    /// `true` si la fase se juega a ida y vuelta.
    var isTwoLegged: Bool {
        switch self {
        case .league, .final: return false
        case .playoff, .r16, .qf, .sf: return true
        }
    }

    /// Nombre completo de la fase, localizado.
    var title: LocalizedStringKey {
        switch self {
        case .league:  return "stage.league"
        case .playoff: return "stage.playoff"
        case .r16:     return "stage.r16"
        case .qf:      return "stage.qf"
        case .sf:      return "stage.sf"
        case .final:   return "stage.final"
        }
    }

    /// Etiqueta corta para las chips del filtro.
    var shortTitle: LocalizedStringKey {
        switch self {
        case .league:  return "stage.league.short"
        case .playoff: return "stage.playoff.short"
        case .r16:     return "stage.r16.short"
        case .qf:      return "stage.qf.short"
        case .sf:      return "stage.sf.short"
        case .final:   return "stage.final.short"
        }
    }

    /// Color del badge de fase. La fase liga es sobria; el cuadro va subiendo
    /// de temperatura hasta la final.
    var accent: Color {
        switch self {
        case .league:  return Color(hex: 0x2C5FE0)
        case .playoff: return Color(hex: 0x5B4BC4)
        case .r16:     return Color(hex: 0x8B3FB0)
        case .qf:      return Color(hex: 0xB83A7E)
        case .sf:      return Color(hex: 0xD1533F)
        case .final:   return Color(hex: 0xD4A03C)
        }
    }
}

// MARK: - Match

/// Un partido del torneo con sus metadatos y, si ya se jugó, el detalle
/// completo de alineaciones y eventos.
struct Match: Identifiable, Codable, Hashable, Sendable {

    /// Identificador de ESPN. Estable entre actualizaciones, a diferencia del
    /// UUID que usaba la app del Mundial.
    let id: String
    /// Hora local de Madrid, `HH:mm`.
    let time: String
    /// Nombre canónico del equipo local (ver `Teams`).
    let home: String
    /// Nombre canónico del equipo visitante.
    let away: String
    /// Fase del torneo.
    let stage: Stage
    /// Jornada 1-8 en la fase liga; `nil` en eliminatorias.
    let matchday: Int?
    /// Identificador de la eliminatoria (`"r16-3"`). `nil` en fase liga y final.
    let tieId: String?
    /// 1 = ida, 2 = vuelta. `nil` a partido único.
    let leg: Int?
    /// Canal de televisión en España. Se cura a mano: ESPN solo da EE.UU.
    let tv: String?
    /// `true` cuando el partido ha terminado.
    let done: Bool
    /// Resultado final `"G-G"`, ya terminado el partido.
    let result: String?
    /// Marcador global de la eliminatoria tras la vuelta, `"G-G"`.
    let aggregate: String?
    /// Resultado de la tanda de penaltis, `"G-G"`, si la hubo.
    let shootout: String?
    /// Alineaciones y eventos. Solo en partidos jugados o en juego.
    let details: MatchDetails?
    /// Estadio.
    let stadium: String?
    /// Ciudad de la sede.
    let venueCity: String?

    // Estado en vivo. Son `var` porque el store los refresca en caliente.

    /// `"pre"` sin empezar · `"in"` en juego · `"post"` terminado.
    var state: String?
    /// Minuto en curso tal como lo da ESPN: `"45'+2'"`.
    var clock: String?
    /// Descripción del estado en inglés (`"Halftime"`, `"First Half"`…).
    var statusText: String?

    // MARK: Derivados

    /// El partido se está jugando ahora mismo.
    var isLive: Bool { state == "in" && !done }

    /// Goles del equipo local, si hay resultado.
    var homeScore: Int? { Self.split(result)?.0 }

    /// Goles del equipo visitante, si hay resultado.
    var awayScore: Int? { Self.split(result)?.1 }

    /// Marcador global de la eliminatoria, desglosado.
    var aggregateScore: (Int, Int)? { Self.split(aggregate) }

    /// Marcador de la tanda de penaltis, desglosado.
    var shootoutScore: (Int, Int)? { Self.split(shootout) }

    /// Divide un `"2-1"` en sus dos números.
    private static func split(_ raw: String?) -> (Int, Int)? {
        guard let raw, let dash = raw.firstIndex(of: "-"),
              let a = Int(raw[raw.startIndex..<dash]),
              let b = Int(raw[raw.index(after: dash)...]) else { return nil }
        return (a, b)
    }

    /// Texto de la columna de estado mientras el partido está en juego.
    /// Devuelve `nil` si el partido no está en directo.
    var liveLabel: LocalizedStringKey? {
        guard isLive else { return nil }
        if let t = statusText?.lowercased() {
            if t.contains("halftime") { return "match.halftime" }
            if t.contains("delayed")  { return "match.delayed" }
        }
        if let c = clock, !c.isEmpty { return LocalizedStringKey(c) }
        return "match.live"
    }

    /// `true` cuando los dos equipos están confirmados. En un cuadro recién
    /// publicado puede haber huecos a la espera del sorteo.
    var hasConfirmedTeams: Bool {
        !home.isEmpty && !away.isEmpty && home != "?" && away != "?"
    }

    // MARK: Codable

    enum CodingKeys: String, CodingKey {
        case id, time, home, away, stage, matchday, tieId, leg, tv
        case done, result, aggregate, shootout, details, stadium, venueCity
        case state, clock, statusText
    }

    /// Decodificación defensiva: cualquier campo puede faltar en un JSON
    /// generado por una versión anterior del script, y la app no debe caerse
    /// por ello.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(String.self, forKey: .id)
        time      = try c.decodeIfPresent(String.self, forKey: .time) ?? "--:--"
        home      = try c.decodeIfPresent(String.self, forKey: .home) ?? ""
        away      = try c.decodeIfPresent(String.self, forKey: .away) ?? ""
        stage     = try c.decodeIfPresent(Stage.self, forKey: .stage) ?? .league
        matchday  = try c.decodeIfPresent(Int.self, forKey: .matchday)
        tieId     = try c.decodeIfPresent(String.self, forKey: .tieId)
        leg       = try c.decodeIfPresent(Int.self, forKey: .leg)
        tv        = try c.decodeIfPresent(String.self, forKey: .tv)
        done      = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        result    = try c.decodeIfPresent(String.self, forKey: .result)
        aggregate = try c.decodeIfPresent(String.self, forKey: .aggregate)
        shootout  = try c.decodeIfPresent(String.self, forKey: .shootout)
        details   = try c.decodeIfPresent(MatchDetails.self, forKey: .details)
        stadium   = try c.decodeIfPresent(String.self, forKey: .stadium)
        venueCity = try c.decodeIfPresent(String.self, forKey: .venueCity)
        state     = try c.decodeIfPresent(String.self, forKey: .state)
        clock     = try c.decodeIfPresent(String.self, forKey: .clock)
        statusText = try c.decodeIfPresent(String.self, forKey: .statusText)
    }

    /// Inicializador directo, para pruebas y vistas previas.
    init(id: String, time: String, home: String, away: String,
         stage: Stage = .league, matchday: Int? = nil,
         tieId: String? = nil, leg: Int? = nil, tv: String? = nil,
         done: Bool = false, result: String? = nil,
         aggregate: String? = nil, shootout: String? = nil,
         details: MatchDetails? = nil, stadium: String? = nil,
         venueCity: String? = nil, state: String? = nil,
         clock: String? = nil, statusText: String? = nil) {
        self.id = id; self.time = time; self.home = home; self.away = away
        self.stage = stage; self.matchday = matchday
        self.tieId = tieId; self.leg = leg; self.tv = tv
        self.done = done; self.result = result
        self.aggregate = aggregate; self.shootout = shootout
        self.details = details; self.stadium = stadium; self.venueCity = venueCity
        self.state = state; self.clock = clock; self.statusText = statusText
    }
}

// MARK: - MatchDay

/// Partidos disputados en una misma fecha.
struct MatchDay: Identifiable, Codable, Hashable, Sendable {
    var id: String { date }
    /// Fecha ISO `yyyy-MM-dd`.
    let date: String
    /// Jornada de la fase liga, si aplica.
    let matchday: Int?
    /// Fase predominante del día.
    let stage: Stage
    /// Partidos del día, en orden cronológico.
    let games: [Match]

    enum CodingKeys: String, CodingKey { case date, matchday, stage, games }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date     = try c.decode(String.self, forKey: .date)
        matchday = try c.decodeIfPresent(Int.self, forKey: .matchday)
        stage    = try c.decodeIfPresent(Stage.self, forKey: .stage) ?? .league
        games    = try c.decodeIfPresent([Match].self, forKey: .games) ?? []
    }

    init(date: String, matchday: Int?, stage: Stage, games: [Match]) {
        self.date = date; self.matchday = matchday
        self.stage = stage; self.games = games
    }

    /// Fecha convertida a `Date`, para comparar con hoy.
    var parsedDate: Date? { Self.formatter.date(from: date) }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        return f
    }()
}

// MARK: - Detalle del partido

/// Alineaciones y sucesos de un partido.
struct MatchDetails: Codable, Hashable, Sendable {
    let homeLineup: TeamLineup?
    let awayLineup: TeamLineup?
    let events: [MatchEvent]?
    /// Estadísticas de equipo (posesión, tiros, faltas…).
    let teamStats: [TeamStat]?
    /// Tanda de penaltis, tiro a tiro.
    let penalties: [PenaltyKick]?
}

/// Alineación de un equipo en un partido.
struct TeamLineup: Codable, Hashable, Sendable {
    let formation: String?
    let players: [LineupPlayer]

    var starters: [LineupPlayer] { players.filter(\.isStarter) }
    var substitutes: [LineupPlayer] { players.filter { !$0.isStarter } }
}

/// Jugador dentro de una alineación, con lo que hizo en el partido.
struct LineupPlayer: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let jersey: Int?
    let name: String
    /// Posición abreviada: `"POR"`, `"DEF"`, `"MED"`, `"DEL"`.
    let position: String?
    let isStarter: Bool
    let events: [MatchEvent]?
    /// Identificador del jugador en ESPN, para su ficha.
    let athleteID: String?
}

/// Suceso puntual del partido.
struct MatchEvent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: MatchEventType
    /// Minuto reglamentario.
    let minute: Int
    /// Minutos de descuento, si el suceso ocurrió en el añadido.
    let extraTime: Int?
    let playerName: String?
    /// Segundo jugador implicado: quien sale en una sustitución, quien asiste
    /// en un gol.
    let relatedPlayer: String?
    let teamName: String?
    let text: String?

    /// Minuto formateado para la interfaz: `"31'"`, `"45+2'"`.
    var displayMinute: String {
        if let extraTime, extraTime > 0 { return "\(minute)+\(extraTime)'" }
        return "\(minute)'"
    }
}

/// Tipo de suceso. Los `rawValue` los escribe el script de actualización.
enum MatchEventType: String, Codable, Sendable {
    case goal = "GOAL"
    case ownGoal = "OWN_GOAL"
    case penalty = "PENALTY"
    case missedPenalty = "MISSED_PENALTY"
    case yellowCard = "YELLOW_CARD"
    case redCard = "RED_CARD"
    case substitution = "SUBSTITUTION"

    /// Símbolo SF Symbols asociado. Se prefiere a los emoji: acompaña al
    /// Dynamic Type y se tiñe con el color que toque.
    var symbolName: String {
        switch self {
        case .goal, .penalty:  return "soccerball"
        case .ownGoal:         return "soccerball.inverse"
        case .missedPenalty:   return "xmark.circle"
        case .yellowCard, .redCard: return "rectangle.portrait.fill"
        case .substitution:    return "arrow.left.arrow.right"
        }
    }

    var tint: Color {
        switch self {
        case .goal, .penalty:  return Color(hex: 0x2FA36B)
        case .ownGoal:         return Color(hex: 0xC0563E)
        case .missedPenalty:   return Color(hex: 0xC0563E)
        case .yellowCard:      return Color(hex: 0xE8C33C)
        case .redCard:         return Color(hex: 0xD03A2F)
        case .substitution:    return Color(hex: 0x6E7A96)
        }
    }

    /// `true` si el suceso cambia el marcador.
    var isGoal: Bool {
        switch self {
        case .goal, .ownGoal, .penalty: return true
        default: return false
        }
    }

    /// Etiqueta localizada del tipo de suceso.
    var label: LocalizedStringKey {
        switch self {
        case .goal:          return "event.goal"
        case .ownGoal:       return "event.ownGoal"
        case .penalty:       return "event.penalty"
        case .missedPenalty: return "event.missedPenalty"
        case .yellowCard:    return "event.yellowCard"
        case .redCard:       return "event.redCard"
        case .substitution:  return "event.substitution"
        }
    }
}

/// Una estadística de equipo del partido (posesión, tiros, córners…).
struct TeamStat: Codable, Identifiable, Hashable, Sendable {
    var id: String { key }
    /// Clave de ESPN: `"possessionPct"`, `"totalShots"`…
    let key: String
    let home: String
    let away: String

    /// Etiqueta localizada de la estadística. Las claves desconocidas se
    /// muestran tal cual antes que desaparecer sin dejar rastro.
    var label: LocalizedStringKey { LocalizedStringKey("stat.\(key)") }
}

/// Un lanzamiento de la tanda de penaltis.
struct PenaltyKick: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(team)-\(order)" }
    let team: String
    let order: Int
    let player: String
    let scored: Bool
}

// MARK: - Clasificación

/// Fila de la tabla única de la fase liga.
struct LeagueStanding: Identifiable, Codable, Hashable, Sendable {
    var id: String { team }
    let position: Int
    let team: String
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int

    var goalDifference: Int { goalsFor - goalsAgainst }
    var points: Int { won * 3 + drawn }

    var zone: StandingZone { StandingZone(position: position) }
}

/// Zona de la clasificación en la que cae un equipo.
///
/// El formato de la fase liga es de tabla única: los ocho primeros pasan
/// directos a octavos, del noveno al vigésimo cuarto juegan un play-off, y del
/// vigésimo quinto en adelante quedan eliminados sin red — desde 2024-25 ya no
/// hay repesca a la Europa League.
enum StandingZone: Sendable, Hashable, CaseIterable {
    case direct      // 1-8
    case playoff     // 9-24
    case out         // 25-36

    init(position: Int) {
        switch position {
        case ...8:  self = .direct
        case ...24: self = .playoff
        default:    self = .out
        }
    }

    var color: Color {
        switch self {
        case .direct:  return Color(hex: 0x1B8A4C)
        case .playoff: return Color(hex: 0x2C5FE0)
        case .out:     return Color(hex: 0xC0392B)
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .direct:  return "zone.direct"
        case .playoff: return "zone.playoff"
        case .out:     return "zone.out"
        }
    }
}

// MARK: - Goleadores

/// Entrada del ranking de goleadores o de asistentes.
struct TopScorer: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(player)|\(team)" }
    let player: String
    let team: String
    /// Goles marcados, o asistencias en el ranking de asistentes.
    let goals: Int
    /// Cuántos de esos goles fueron de penalti.
    let penalties: Int?
    let athleteID: String?
}

// MARK: - Snapshot

/// Raíz del JSON que sirve el NAS y, como suplente, GitHub.
struct MatchSnapshot: Codable, Sendable {
    let lastUpdated: String
    let season: String
    let matchDays: [MatchDay]
    let standings: [LeagueStanding]?
    let topScorers: [TopScorer]?
    let topAssists: [TopScorer]?

    enum CodingKeys: String, CodingKey {
        case lastUpdated, season, matchDays, standings, topScorers, topAssists
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lastUpdated = try c.decodeIfPresent(String.self, forKey: .lastUpdated) ?? ""
        season      = try c.decodeIfPresent(String.self, forKey: .season) ?? ""
        matchDays   = try c.decodeIfPresent([MatchDay].self, forKey: .matchDays) ?? []
        standings   = try c.decodeIfPresent([LeagueStanding].self, forKey: .standings)
        topScorers  = try c.decodeIfPresent([TopScorer].self, forKey: .topScorers)
        topAssists  = try c.decodeIfPresent([TopScorer].self, forKey: .topAssists)
    }
}

// MARK: - Temporada

/// Una temporada seleccionable en la app, con sus dos fuentes de datos.
struct AppSeason: Identifiable, Equatable, Hashable, Sendable {
    var id: String { code }
    let code: String
    let displayName: String
    let espnYear: Int
    /// Fuente de siempre: el JSON publicado en GitHub.
    let remoteURL: URL?
    /// Fuente rápida servida por el NAS. Publica en segundos, mientras que la
    /// CDN de GitHub cachea unos cinco minutos. Solo la temporada en curso.
    let fastURL: URL?
    /// Nombre del JSON incrustado en el bundle, sin extensión.
    let seedName: String

    static let all: [AppSeason] = [
        AppSeason(
            code: "2627",
            displayName: "26/27",
            espnYear: 2026,
            remoteURL: URL(string: "https://raw.githubusercontent.com/cornellana/champions-2627/main/data/champions2627.json"),
            fastURL: URL(string: "https://laliga-api.cornellanas.net/datos/champions2627.json"),
            seedName: "champions2627-seed"
        )
    ]

    static var current: AppSeason { all[0] }
}

// MARK: - Selección de jugador

/// Jugador sobre el que se abre la ficha, con el contexto desde el que se pulsó.
struct PlayerSelection: Identifiable, Equatable, Sendable {
    var id: String { "\(playerName)|\(teamName ?? "")|\(athleteID ?? "")" }
    let playerName: String
    let teamName: String?
    let athleteID: String?
    let position: String?
}

// MARK: - Color

extension Color {
    /// Crea un color a partir de un literal `0xRRGGBB`.
    init(hex: UInt) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
