//
//  RosterService.swift
//  Champions
//
//  Plantillas de los clubes, para enseñar algo en la ficha de un partido que
//  todavía no se ha jugado.
//
//  El detalle importante: **la plantilla no se puede pedir por la vía de la
//  Champions**. Pedirle a ESPN los jugadores del Real Madrid dentro de
//  `uefa.champions` devuelve cero; hay que preguntárselos a su liga doméstica,
//  `esp.1`, y entonces devuelve treinta. Por eso cada club lleva apuntada su
//  liga en el catálogo `Teams`.
//
//  Cuatro clubes —Shajtar, Slavia, Slovan y Sabah— juegan en ligas que ESPN no
//  cubre. Para ellos no hay plantilla y la ficha lo dice, en vez de quedarse
//  girando.
//

import Foundation

// MARK: - RosterPlayer

/// Un jugador de la plantilla de un club.
struct RosterPlayer: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let jersey: Int?
    /// Puesto normalizado a cuatro grupos.
    let position: Position

    enum Position: String, CaseIterable, Sendable {
        case goalkeeper, defender, midfielder, forward, unknown

        /// Orden en el que se listan: como se alinea un equipo.
        var order: Int {
            switch self {
            case .goalkeeper: return 0
            case .defender:   return 1
            case .midfielder: return 2
            case .forward:    return 3
            case .unknown:    return 4
            }
        }

        var title: LocalizedStringResource {
            switch self {
            case .goalkeeper: return "position.goalkeepers"
            case .defender:   return "position.defenders"
            case .midfielder: return "position.midfielders"
            case .forward:    return "position.forwards"
            case .unknown:    return "position.others"
            }
        }

        /// Traduce la abreviatura de ESPN al grupo correspondiente.
        init(espn abreviatura: String?) {
            switch (abreviatura ?? "").uppercased() {
            case "G", "GK":
                self = .goalkeeper
            case "D", "DF", "CB", "LB", "RB", "CD", "WB", "LWB", "RWB":
                self = .defender
            case "M", "MF", "CM", "DM", "AM", "LM", "RM":
                self = .midfielder
            case "F", "FW", "ST", "CF", "LW", "RW", "W":
                self = .forward
            default:
                self = .unknown
            }
        }
    }
}

// MARK: - RosterService

/// Descarga y cachea plantillas.
@Observable
@MainActor
final class RosterService {

    static let shared = RosterService()

    /// Plantillas ya descargadas, por nombre canónico de club. Se guardan
    /// mientras viva la app: una plantilla no cambia a media tarde y así
    /// abrir varias fichas del mismo equipo no repite la descarga.
    private var cache: [String: [RosterPlayer]] = [:]

    private init() {}

    /// Devuelve la plantilla de un club, descargándola si hace falta.
    /// - Returns: Los jugadores, o vacío si el club no tiene liga cubierta o
    ///   la petición falla.
    func roster(for team: String) async -> [RosterPlayer] {
        if let guardada = cache[team] { return guardada }

        guard let club = Teams.team(team), let liga = club.domesticLeague else {
            cache[team] = []
            return []
        }

        let base = "https://site.api.espn.com/apis/site/v2/sports/soccer/\(liga)/teams/\(club.espnID)/roster"
        let año = Calendar.current.component(.year, from: Date())

        // ESPN unas veces quiere la temporada y otras no, y en agosto puede que
        // la nueva todavía no esté cargada. Se prueban las tres formas y se
        // acepta la primera que traiga una plantilla creíble.
        for sufijo in ["", "?season=\(año)", "?season=\(año - 1)"] {
            guard let url = URL(string: base + sufijo),
                  let (data, respuesta) = try? await URLSession.shared.data(from: url),
                  (respuesta as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let jugadores = Self.parse(data)
            if jugadores.count >= 10 {
                cache[team] = jugadores
                return jugadores
            }
        }

        cache[team] = []
        return []
    }

    /// Descarga las dos plantillas de un partido a la vez.
    func rosters(home: String, away: String) async -> (home: [RosterPlayer], away: [RosterPlayer]) {
        async let local = roster(for: home)
        async let visitante = roster(for: away)
        return await (local, visitante)
    }

    // MARK: Parseo

    private nonisolated static func parse(_ data: Data) -> [RosterPlayer] {
        struct Respuesta: Decodable {
            let athletes: [Atleta]?
            struct Atleta: Decodable {
                let id: String?
                let displayName: String?
                let fullName: String?
                let jersey: String?
                let position: Puesto?
                struct Puesto: Decodable { let abbreviation: String? }
            }
        }

        guard let respuesta = try? JSONDecoder().decode(Respuesta.self, from: data) else { return [] }

        return (respuesta.athletes ?? []).compactMap { atleta in
            let nombre = atleta.displayName ?? atleta.fullName ?? ""
            guard !nombre.isEmpty else { return nil }
            return RosterPlayer(
                id: atleta.id ?? nombre,
                name: nombre,
                jersey: atleta.jersey.flatMap(Int.init),
                position: .init(espn: atleta.position?.abbreviation)
            )
        }
        .sorted {
            if $0.position.order != $1.position.order { return $0.position.order < $1.position.order }
            return ($0.jersey ?? 999) < ($1.jersey ?? 999)
        }
    }
}
