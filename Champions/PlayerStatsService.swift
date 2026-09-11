//
//  PlayerStatsService.swift
//  Champions
//
//  De dónde sale cada dato de la ficha del jugador. Son dos fuentes, las mismas
//  que usa la app de La Liga:
//
//  · ESPN: el identificador del jugador, su edad y su puesto, y el total de la
//    temporada en la Champions. La media por partido es ese total entre los
//    partidos jugados.
//  · SofaScore: lo que hizo en un partido concreto, la valoración, la foto y el
//    valor de mercado.
//
//  Las dos distinguen clientes, y al revés una de otra. SofaScore responde 403
//  a curl y a Python, pero atiende al URLSession del iPhone si lleva
//  `User-Agent: Mozilla/5.0`, que es justo lo que manda la app de La Liga desde
//  hace meses. ESPN, en cambio, contesta 403 a una cabecera de navegador y
//  atiende a la de serie de URLSession. Por eso la cabecera solo va a
//  SofaScore. Medido todo el 11/09/26.
//

import Foundation

enum PlayerStatsService {

    private static let espnBase = "https://sports.core.api.espn.com/v2/sports/soccer/leagues/uefa.champions"
    private static let sofaBase = "https://api.sofascore.com/api/v1"
    /// La Champions en SofaScore.
    private static let sofaTournament = 7

    // MARK: - ESPN

    /// Identificador de ESPN de un jugador que llega sin él, como los de la
    /// lista de goleadores.
    ///
    /// Primero se busca en las alineaciones ya descargadas: no gasta red y
    /// cubre a los 36 clubes, también a los cuatro cuya liga doméstica no sigue
    /// ESPN y de los que por tanto no hay plantilla. Si no aparece —un jugador
    /// que aún no ha jugado—, se prueba con la plantilla de su liga.
    @MainActor
    static func resolveAthleteID(name: String, team: String?, matchDays: [MatchDay]) async -> String? {
        for day in matchDays.reversed() {
            for game in day.games {
                guard let details = game.details else { continue }
                for (lineup, club) in [(details.homeLineup, game.home), (details.awayLineup, game.away)] {
                    guard let lineup, team == nil || team == club else { continue }
                    if let player = lineup.players.first(where: { sameName($0.name, name) }),
                       let id = player.athleteID, !id.isEmpty {
                        return id
                    }
                }
            }
        }
        guard let team else { return nil }
        let squad = await RosterService.shared.roster(for: team)
        return squad.first { sameName($0.name, name) && $0.id.allSatisfy(\.isNumber) }?.id
    }

    /// Edad y puesto. Se piden a la ficha del atleta y no a la plantilla de su
    /// club porque la ficha existe para todos, también para los jugadores de
    /// ligas que ESPN no cubre: un portero del Slovan sale con su edad igual
    /// que Mbappé.
    static func athleteInfo(id: String?) async -> (age: Int?, position: String?) {
        guard let id, !id.isEmpty,
              let json = await fetch("\(espnBase)/athletes/\(id)") else { return (nil, nil) }
        let position = (json["position"] as? [String: Any])?["abbreviation"] as? String
        return (number(json["age"]).map { Int($0) }, position)
    }

    /// Total de la temporada en la Champions, concepto a concepto.
    ///
    /// ESPN parte la temporada en seis tipos, uno por fase —liga, play-off,
    /// octavos, cuartos, semifinales y final—, lo que invitaba a pensar que el
    /// tipo 1 solo sumaría la fase liga y que en febrero el total mentiría. No
    /// es así: medido con Mbappé en la 25/26 ya terminada, los tipos 0 y 1 dan
    /// lo mismo —11 partidos y 15 goles, la temporada entera— y del 2 al 6 no
    /// hay nada por jugador. Se pide el 0, que es el total por definición, y el
    /// 1 queda de reserva.
    static func seasonStats(athleteID: String?, season: AppSeason) async -> [String: Double] {
        guard let athleteID, !athleteID.isEmpty else { return [:] }
        for type in [0, 1] {
            let url = "\(espnBase)/seasons/\(season.espnYear)/types/\(type)/athletes/\(athleteID)/statistics/0"
            guard let json = await fetch(url) else { continue }
            var values: [String: Double] = [:]
            let categories = (json["splits"] as? [String: Any])?["categories"] as? [[String: Any]] ?? []
            for category in categories {
                for stat in category["stats"] as? [[String: Any]] ?? [] {
                    if let name = stat["name"] as? String, let value = number(stat["value"]) {
                        values[name] = value
                    }
                }
            }
            if !values.isEmpty { return values }
        }
        return [:]
    }

    // MARK: - SofaScore

    /// Un jugador dentro de la alineación de SofaScore de un partido.
    struct MatchPlayer: Sendable {
        let playerID: Int?
        let stats: [String: Double]
    }

    /// Lo que hizo el jugador en el partido desde el que se abrió la ficha.
    static func matchPlayer(for selection: PlayerSelection, season: AppSeason) async -> MatchPlayer? {
        guard let match = selection.match, match.done,
              let eventID = await eventID(for: match, season: season) else { return nil }
        let isHome: Bool? = selection.teamName == match.home ? true
                          : selection.teamName == match.away ? false : nil
        return await lineupPlayer(eventID: eventID, name: selection.playerName,
                                  jersey: selection.jersey, isHome: isHome)
    }

    /// El partido equivalente en SofaScore.
    ///
    /// La app de La Liga lo busca por número de jornada, y en la Champions eso
    /// no basta: SofaScore llama «round 5» a la jornada 5 de la fase liga y
    /// también a los octavos. La fase liga se sigue buscando por jornada; las
    /// eliminatorias, por ronda **y** slug, con el número de ronda sacado de la
    /// propia lista de rondas en vez de fijado aquí, porque solo se ha podido
    /// ver en la temporada anterior.
    static func eventID(for match: Match, season: AppSeason) async -> Int? {
        guard let seasonID = season.sofascoreSeasonID else { return nil }
        let base = "\(sofaBase)/unique-tournament/\(sofaTournament)/season/\(seasonID)"

        let url: String
        if match.stage == .league {
            guard let matchday = match.matchday else { return nil }
            url = "\(base)/events/round/\(matchday)"
        } else {
            // Hay dos «playoff-round»: la previa, con el prefijo
            // «Qualification», y la eliminatoria de verdad, sin prefijo.
            guard let slug = slug(for: match.stage),
                  let rounds = (await fetch("\(base)/rounds", sofaScore: true))?["rounds"] as? [[String: Any]],
                  let round = rounds.last(where: {
                      ($0["slug"] as? String) == slug && ($0["prefix"] as? String) == nil
                  })?["round"] as? Int
            else { return nil }
            url = "\(base)/events/round/\(round)/slug/\(slug)"
        }

        let events = (await fetch(url, sofaScore: true))?["events"] as? [[String: Any]] ?? []
        let candidates = events.filter { event in
            guard let home = (event["homeTeam"] as? [String: Any])?["name"] as? String,
                  let away = (event["awayTeam"] as? [String: Any])?["name"] as? String else { return false }
            return sameTeam(sofaScore: home, app: match.home) && sameTeam(sofaScore: away, app: match.away)
        }
        // Uno y solo uno. Ante la duda, mejor la ficha sin columna del partido
        // que con los números de otro partido.
        guard candidates.count == 1 else { return nil }
        return candidates[0]["id"] as? Int
    }

    private static func slug(for stage: Stage) -> String? {
        switch stage {
        case .league:  return nil
        case .playoff: return "playoff-round"
        case .r16:     return "round-of-16"
        case .qf:      return "quarterfinals"
        case .sf:      return "semifinals"
        case .final:   return "final"
        }
    }

    /// Busca al jugador en la alineación de SofaScore del partido.
    ///
    /// Por nombre, como la app de La Liga, y si no casa, por dorsal: ESPN y
    /// SofaScore no siempre escriben igual un nombre, pero el dorsal es el
    /// mismo en los dos. El dorsal solo vale sabiendo el equipo, porque el 9
    /// lo lleva uno en cada lado.
    private static func lineupPlayer(eventID: Int, name: String, jersey: Int?, isHome: Bool?) async -> MatchPlayer? {
        guard let json = await fetch("\(sofaBase)/event/\(eventID)/lineups", sofaScore: true) else { return nil }
        let sides = isHome.map { $0 ? ["home"] : ["away"] } ?? ["home", "away"]

        for side in sides {
            let players = (json[side] as? [String: Any])?["players"] as? [[String: Any]] ?? []
            let byName = players.first {
                sameName((($0["player"] as? [String: Any])?["name"] as? String) ?? "", name)
            }
            let byJersey: [String: Any]? = isHome == nil ? nil : jersey.flatMap { dorsal in
                players.first { number($0["shirtNumber"]).map { Int($0) } == dorsal }
            }
            guard let player = byName ?? byJersey else { continue }

            var stats: [String: Double] = [:]
            for (key, value) in player["statistics"] as? [String: Any] ?? [:] {
                if let n = number(value) { stats[key] = n }
            }
            return MatchPlayer(playerID: (player["player"] as? [String: Any])?["id"] as? Int, stats: stats)
        }
        return nil
    }

    /// El jugador en el buscador de SofaScore, para cuando no se abre desde un
    /// partido. Si hay varios con el mismo nombre, el de su club.
    static func searchPlayer(name: String, team: String?) async -> Int? {
        guard let query = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let json = await fetch("\(sofaBase)/search/\(query)", sofaScore: true) else { return nil }
        let players = (json["results"] as? [[String: Any]] ?? [])
            .filter { ($0["type"] as? String) == "player" }
            .compactMap { $0["entity"] as? [String: Any] }
            .filter { sameName(($0["name"] as? String) ?? "", name) }
        if let team, let fromClub = players.first(where: {
            guard let club = ($0["team"] as? [String: Any])?["name"] as? String else { return false }
            return sameTeam(sofaScore: club, app: team)
        }) {
            return fromClub["id"] as? Int
        }
        return players.first?["id"] as? Int
    }

    /// Valor de mercado, en euros.
    static func marketValue(playerID: Int) async -> Int? {
        let json = await fetch("\(sofaBase)/player/\(playerID)", sofaScore: true)
        return number((json?["player"] as? [String: Any])?["proposedMarketValue"]).map { Int($0) }
    }

    /// Valoración media en la Champions de esta temporada.
    static func seasonRating(playerID: Int, season: AppSeason) async -> Double? {
        guard let seasonID = season.sofascoreSeasonID else { return nil }
        let url = "\(sofaBase)/player/\(playerID)/unique-tournament/\(sofaTournament)/season/\(seasonID)/statistics/overall"
        let json = await fetch(url, sofaScore: true)
        return number((json?["statistics"] as? [String: Any])?["rating"])
    }

    // MARK: - Nombres

    /// Minúsculas y sin tildes, para comparar nombres de dos fuentes distintas.
    static func fold(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }

    /// Mismo jugador: un nombre contiene al otro, como en la app de La Liga.
    static func sameName(_ a: String, _ b: String) -> Bool {
        let x = fold(a), y = fold(b)
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x.contains(y) || y.contains(x)
    }

    /// Los cuatro clubes que la app nombra en castellano y SofaScore en su
    /// forma oficial. Medido el 11/09/26 contra la jornada 1, en la que juegan
    /// los 36: con el algoritmo de La Liga casan 14 de los 18 partidos, y con
    /// estos cuatro alias, los 18.
    private static let aliases: [String: String] = [
        "aek atenas": "aek athens",
        "brujas":     "club brugge",
        "oporto":     "fc porto",
        "napoles":    "napoli",
    ]

    /// Mismo club. Es el algoritmo de la app de La Liga —contener el nombre, o
    /// cualquiera de sus palabras de más de tres letras— más los alias.
    static func sameTeam(sofaScore: String, app: String) -> Bool {
        let theirs = fold(sofaScore)
        let ours = aliases[fold(app)] ?? fold(app)
        if theirs.contains(ours) || ours.contains(theirs) { return true }
        return ours.split(separator: " ").filter { $0.count > 3 }.contains { theirs.contains($0) }
    }

    // MARK: - Red

    private static func fetch(_ url: String, sofaScore: Bool = false) async -> [String: Any]? {
        guard let address = URL(string: url) else { return nil }
        var request = URLRequest(url: address)
        request.timeoutInterval = 12
        if sofaScore { request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
