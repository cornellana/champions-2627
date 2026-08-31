//
//  MatchStore.swift
//  Champions
//
//  Almacén observable de los datos del torneo.
//
//  La carga va en cascada, igual que en la app de La Liga: memoria → caché en
//  disco → red → semilla del bundle. La red intenta primero el NAS, que publica
//  en segundos, y cae a GitHub si no contesta rápido.
//

import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
final class MatchStore {

    // MARK: Estado observable

    private(set) var selectedSeason: AppSeason = .current

    /// `true` mientras no hay nada que enseñar. No se activa en los refrescos
    /// silenciosos: si ya hay datos en pantalla, no se parpadea.
    var isLoading = true

    /// Mensaje de error para la barra superior, o `nil`.
    var errorMessage: LocalizedStringKey?

    /// Marca de la última actualización recibida.
    private(set) var lastUpdated: Date?

    /// De dónde salieron los datos que hay ahora en pantalla.
    private(set) var source: DataSource = .none

    /// `true` si el último intento de refresco no llegó a buen puerto.
    ///
    /// Sin esto, un fallo que no sea de red conocida —una respuesta rara, un
    /// JSON que no decodifica— deja la app callada con los datos viejos, y
    /// desde fuera parece que simplemente no hay novedades. Le pasó a la app
    /// de La Liga el 31/08/26 con dos partidos en juego.
    private(set) var lastRefreshFailed = false

    /// Origen de los datos en curso, para el indicador de la cabecera.
    enum DataSource: Sendable {
        case none, seed, cache, github, nas

        var label: LocalizedStringKey? {
            switch self {
            case .none, .cache: return nil
            case .seed:   return "source.seed"
            case .github: return "source.github"
            case .nas:    return "source.live"
            }
        }
    }

    // MARK: Datos

    private var cache: [String: MatchSnapshot] = [:]

    var snapshot: MatchSnapshot? { cache[selectedSeason.code] }
    var matchDays: [MatchDay] { snapshot?.matchDays ?? [] }
    var topScorers: [TopScorer] { snapshot?.topScorers ?? [] }
    var topAssists: [TopScorer] { snapshot?.topAssists ?? [] }

    /// Todos los partidos del torneo, en orden cronológico.
    var allMatches: [Match] { matchDays.flatMap(\.games) }

    /// Clasificación: la que publica ESPN si viene, y si no la calculada aquí.
    ///
    /// La calculada existe porque durante una jornada en juego la tabla remota
    /// puede ir por detrás de los resultados que ya se ven en la lista, y una
    /// app que se contradice a sí misma no inspira ninguna confianza.
    var standings: [LeagueStanding] {
        if let remote = snapshot?.standings, !remote.isEmpty,
           remote.contains(where: { $0.played > 0 }) {
            return remote
        }
        return computedStandings()
    }

    // MARK: Refresco

    /// Carga los datos siguiendo la cascada completa.
    func refresh() async {
        let season = selectedSeason
        errorMessage = nil

        // Ya hay datos en memoria: refrescar por detrás sin tocar la interfaz.
        if cache[season.code] != nil {
            await remoteRefresh(season)
            return
        }

        isLoading = true

        // Algo que enseñar antes de tocar la red: la caché del disco si la hay
        // y, si no, la semilla que viaja en el propio binario.
        //
        // La semilla va **antes** de la red y no después como último recurso.
        // Puesta detrás, una instalación limpia sin cobertura se quedaba veinte
        // segundos en «Cargando…» esperando a que venciera el tiempo de espera,
        // teniendo el calendario entero dentro del teléfono desde el principio.
        if let cached = loadFromDisk(season) {
            cache[season.code] = cached
            applyMeta(cached, source: .cache)
        } else if let seed = loadSeed(season) {
            cache[season.code] = seed
            applyMeta(seed, source: .seed)
        }
        isLoading = false

        await remoteRefresh(season)
    }

    /// Refresca desde la red sin bloquear la interfaz.
    private func remoteRefresh(_ season: AppSeason) async {
        do {
            let (fresh, origin) = try await fetchRemote(season)
            cache[season.code] = fresh
            applyMeta(fresh, source: origin)
            saveToDisk(fresh, season: season)
            errorMessage = nil
            lastRefreshFailed = false
        } catch {
            lastRefreshFailed = true
            // Si ya hay datos en pantalla, un fallo de red no debe alarmar:
            // basta con seguir enseñando lo que había.
            if cache[season.code] == nil {
                errorMessage = "error.noConnection"
            } else if let urlError = error as? URLError,
                      [.notConnectedToInternet, .networkConnectionLost].contains(urlError.code) {
                errorMessage = "error.offline"
            }
        }
        isLoading = false
    }

    private func applyMeta(_ snapshot: MatchSnapshot, source: DataSource) {
        self.source = source
        self.lastUpdated = Self.isoFormatter.date(from: snapshot.lastUpdated)
    }

    /// Antigüedad del dato que hay en pantalla, o `nil` si no se sabe.
    var dataAge: TimeInterval? {
        lastUpdated.map { Date().timeIntervalSince($0) }
    }

    // MARK: Red

    /// Primero el NAS, que publica en segundos; si no contesta, GitHub.
    ///
    /// La app no puede quedar atada a que el NAS o la fibra de casa estén en
    /// pie: el intento rápido lleva un límite corto y cualquier fallo —red,
    /// contenedor caído, datos caducados (el NAS responde 503 a propósito)—
    /// cae en silencio a la fuente de siempre.
    private func fetchRemote(_ season: AppSeason) async throws -> (MatchSnapshot, DataSource) {
        if let fast = season.fastURL,
           let data = try? await download(fast, timeout: 4),
           let snapshot = try? decode(data) {
            return (snapshot, .nas)
        }
        guard let base = season.remoteURL else { throw URLError(.badURL) }
        return (try decode(try await download(base, timeout: 20)), .github)
    }

    private nonisolated func download(_ base: URL, timeout: TimeInterval) async throws -> Data {
        // El sufijo temporal esquiva cachés intermedias; la de GitHub las tiene.
        guard let url = URL(string: "\(base.absoluteString)?t=\(Int(Date().timeIntervalSince1970))") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private nonisolated func decode(_ data: Data) throws -> MatchSnapshot {
        try JSONDecoder().decode(MatchSnapshot.self, from: data)
    }

    // MARK: Caché en disco
    //
    // En disco y no en `UserDefaults`: el JSON del torneo completo, con las
    // alineaciones de 189 partidos, ronda los dos megas y medio, y ese no es
    // tamaño para la base de preferencias.

    private func cacheURL(_ season: AppSeason) -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent("champions_\(season.code)_v1.json")
    }

    private func loadFromDisk(_ season: AppSeason) -> MatchSnapshot? {
        guard let url = cacheURL(season),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    private func saveToDisk(_ snapshot: MatchSnapshot, season: AppSeason) {
        guard let url = cacheURL(season),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: Semilla del bundle

    private func loadSeed(_ season: AppSeason) -> MatchSnapshot? {
        guard let url = Bundle.main.url(forResource: season.seedName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    // MARK: Clasificación calculada

    /// Reconstruye la tabla de 36 desde los resultados conocidos.
    private func computedStandings() -> [LeagueStanding] {
        struct Row { var w = 0, d = 0, l = 0, gf = 0, ga = 0 }
        var rows: [String: Row] = [:]

        // Todos los equipos aparecen aunque no hayan jugado: una tabla a la que
        // le faltan filas al principio del torneo se lee como un error.
        for team in Teams.all { rows[team.key] = Row() }

        for match in allMatches where match.stage == .league && match.done {
            guard let hs = match.homeScore, let aws = match.awayScore else { continue }
            var home = rows[match.home] ?? Row()
            var away = rows[match.away] ?? Row()
            if hs > aws { home.w += 1; away.l += 1 }
            else if hs < aws { home.l += 1; away.w += 1 }
            else { home.d += 1; away.d += 1 }
            home.gf += hs; home.ga += aws
            away.gf += aws; away.ga += hs
            rows[match.home] = home
            rows[match.away] = away
        }

        let sorted = rows
            .map { team, r in
                LeagueStanding(position: 0, team: team,
                               played: r.w + r.d + r.l,
                               won: r.w, drawn: r.d, lost: r.l,
                               goalsFor: r.gf, goalsAgainst: r.ga)
            }
            .sorted {
                if $0.points != $1.points { return $0.points > $1.points }
                if $0.goalDifference != $1.goalDifference { return $0.goalDifference > $1.goalDifference }
                if $0.goalsFor != $1.goalsFor { return $0.goalsFor > $1.goalsFor }
                return Teams.name($0.team) < Teams.name($1.team)
            }

        return sorted.enumerated().map { index, row in
            LeagueStanding(position: index + 1, team: row.team,
                           played: row.played, won: row.won, drawn: row.drawn,
                           lost: row.lost, goalsFor: row.goalsFor,
                           goalsAgainst: row.goalsAgainst)
        }
    }

    // MARK: Consultas

    /// Jornadas de la fase liga que ya tienen partidos publicados.
    var availableMatchdays: [Int] {
        Array(Set(allMatches.compactMap(\.matchday))).sorted()
    }

    /// Fases que ya tienen algún partido en el calendario.
    var availableStages: [Stage] {
        let present = Set(allMatches.map(\.stage))
        return Stage.allCases.filter(present.contains).sorted { $0.order < $1.order }
    }

    /// Partidos de un equipo, en orden cronológico.
    func matches(for team: String) -> [(day: MatchDay, match: Match)] {
        matchDays.flatMap { day in
            day.games
                .filter { $0.home == team || $0.away == team }
                .map { (day, $0) }
        }
    }

    /// Los cinco últimos resultados de un equipo, del más reciente al más viejo.
    /// - Returns: `"W"`, `"D"` o `"L"` por partido.
    func form(for team: String) -> [String] {
        matches(for: team)
            .compactMap { _, match -> String? in
                guard match.done, let hs = match.homeScore, let aws = match.awayScore else { return nil }
                let isHome = match.home == team
                let own = isHome ? hs : aws
                let rival = isHome ? aws : hs
                if own > rival { return "W" }
                if own < rival { return "L" }
                return "D"
            }
            .suffix(5)
            .reversed()
    }

    /// Las eliminatorias de una fase, agrupadas por `tieId`.
    ///
    /// Devuelve los dos partidos de cada cruce en orden —ida y vuelta—, o uno
    /// solo si el sorteo aún no ha publicado la vuelta.
    func ties(in stage: Stage) -> [(id: String, legs: [Match])] {
        let games = allMatches.filter { $0.stage == stage }
        guard stage != .final else {
            return games.map { ($0.id, [$0]) }
        }
        var grouped: [String: [Match]] = [:]
        for game in games {
            grouped[game.tieId ?? game.id, default: []].append(game)
        }
        return grouped
            .map { (id: $0.key, legs: $0.value.sorted { ($0.leg ?? 1) < ($1.leg ?? 1) }) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// La fecha a la que conviene desplazar la lista al abrir la app: la del
    /// primer día con partidos que no haya terminado todavía.
    var focusDate: String? {
        let today = Self.dayFormatter.string(from: Date())
        return matchDays.first { $0.date >= today }?.date ?? matchDays.last?.date
    }

    // MARK: Formateadores

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        return f
    }()
}
