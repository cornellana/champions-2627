//
//  MatchPrediction.swift
//  Champions
//
//  Pronóstico de los partidos que aún no se han jugado.
//
//  Modelo de Poisson bivariante, el mismo que la app de La Liga: se deduce la
//  fuerza atacante y defensiva de cada equipo a partir de los resultados que ya
//  hay, se convierten en goles esperados y se recorre la matriz de marcadores
//  para sumar las probabilidades de victoria, empate y derrota.
//
//  La diferencia con La Liga es de dónde salen los datos. Allí hay tres
//  temporadas en el bundle y un *prior* sólido desde el primer día; aquí la
//  competición empieza de cero cada año y en la jornada 1 no hay ni un partido
//  jugado. Para no dejar la pantalla vacía justo cuando más se mira, el motor
//  arranca con la ventaja de campo sola y va afinando conforme llegan
//  resultados — y lo dice, en vez de aparentar una certeza que no tiene.
//

import Foundation

// MARK: - Salida

/// Una fila del desglose: qué se ha mirado y cuánto vale en cada equipo.
struct PredictionFactor: Identifiable, Sendable {
    let id = UUID()
    /// Clave del catálogo de idiomas.
    let labelKey: String
    let homeValue: String
    let awayValue: String
}

/// Probabilidades de resultado —suman 1— y los factores que las explican.
struct MatchPrediction: Sendable {
    let homeWin: Double
    let draw: Double
    let awayWin: Double
    let factors: [PredictionFactor]
    /// Partidos de la fase liga ya jugados sobre los que se ha calculado.
    let sampleSize: Int

    var homePercent: Int { Int((homeWin * 100).rounded()) }
    var drawPercent: Int { Int((draw * 100).rounded()) }
    var awayPercent: Int { Int((awayWin * 100).rounded()) }

    /// `true` cuando todavía no hay resultados y el pronóstico es solo la
    /// ventaja de jugar en casa. Conviene decirlo en pantalla.
    var isBaselineOnly: Bool { sampleSize == 0 }
}

// MARK: - Motor

enum PredictionEngine {

    /// Goles por equipo que se consideran en la matriz de probabilidad.
    /// Por encima de ocho la probabilidad es despreciable.
    private static let maxGoals = 8

    /// Partidos "virtuales" de regresión a la media.
    ///
    /// Con ocho partidos por equipo en toda la fase liga, la muestra es
    /// pequeñísima: sin este freno, un 4-0 en la primera jornada convertiría a
    /// cualquiera en el mejor ataque de Europa.
    private static let shrinkage = 4.0

    /// Medias de la competición cuando no hay ni un partido jugado. Salen del
    /// histórico de la fase de grupos: algo más de goles que en una liga
    /// doméstica y una ventaja de campo parecida.
    private static let fallbackHomeAvg = 1.55
    private static let fallbackAwayAvg = 1.20

    /// Calcula el pronóstico de un partido.
    /// - Parameters:
    ///   - match: Partido a estimar. Debe estar sin jugar.
    ///   - matchDays: Calendario completo, de donde salen los resultados.
    /// - Returns: El pronóstico, o `nil` si el partido ya se jugó.
    static func predict(match: Match, matchDays: [MatchDay]) -> MatchPrediction? {
        guard !match.done else { return nil }

        let tasas = agregar(matchDays)

        let mediaLocal = tasas.matches > 0 ? tasas.leagueHomeAvg : fallbackHomeAvg
        let mediaVisitante = tasas.matches > 0 ? tasas.leagueAwayAvg : fallbackAwayAvg

        let ataqueLocal = fuerza(tasas.attack(match.home), partidos: tasas.games[match.home] ?? 0)
        let defensaLocal = fuerza(tasas.defense(match.home), partidos: tasas.games[match.home] ?? 0)
        let ataqueVisitante = fuerza(tasas.attack(match.away), partidos: tasas.games[match.away] ?? 0)
        let defensaVisitante = fuerza(tasas.defense(match.away), partidos: tasas.games[match.away] ?? 0)

        // Goles esperados de cada equipo. El suelo evita que un equipo al que
        // aún no le han marcado salga con probabilidad cero de encajar.
        let lambdaLocal = max(0.15, ataqueLocal * defensaVisitante * mediaLocal)
        let lambdaVisitante = max(0.15, ataqueVisitante * defensaLocal * mediaVisitante)

        var pLocal = 0.0, pEmpate = 0.0, pVisitante = 0.0
        for i in 0...maxGoals {
            for j in 0...maxGoals {
                let p = poisson(i, lambdaLocal) * poisson(j, lambdaVisitante)
                if i > j { pLocal += p } else if i < j { pVisitante += p } else { pEmpate += p }
            }
        }
        let total = pLocal + pEmpate + pVisitante
        guard total > 0 else { return nil }

        // En una eliminatoria a doble partido el empate no decide nada, pero
        // este pronóstico es del partido, no del cruce: se deja tal cual y el
        // desglose enseña el global cuando lo hay.
        return MatchPrediction(
            homeWin: pLocal / total,
            draw: pEmpate / total,
            awayWin: pVisitante / total,
            factors: desglose(match: match, matchDays: matchDays, tasas: tasas,
                              lambdaLocal: lambdaLocal, lambdaVisitante: lambdaVisitante),
            sampleSize: tasas.matches
        )
    }

    // MARK: Fuerzas

    /// Mezcla la fuerza medida con la media de la competición según cuántos
    /// partidos haya detrás. Sin partidos devuelve 1.0, o sea "del montón".
    private static func fuerza(_ medida: Double?, partidos: Int) -> Double {
        guard let medida else { return 1.0 }
        let peso = Double(partidos) / (Double(partidos) + shrinkage)
        return peso * medida + (1 - peso) * 1.0
    }

    // MARK: Agregación

    private struct Tasas {
        var gf: [String: Int] = [:]
        var ga: [String: Int] = [:]
        var games: [String: Int] = [:]
        var homeGoals = 0
        var awayGoals = 0
        var matches = 0

        var leagueHomeAvg: Double { matches > 0 ? Double(homeGoals) / Double(matches) : 0 }
        var leagueAwayAvg: Double { matches > 0 ? Double(awayGoals) / Double(matches) : 0 }
        /// Goles que marca un equipo por partido, de media.
        var perTeamAvg: Double { matches > 0 ? Double(homeGoals + awayGoals) / Double(matches * 2) : 0 }

        /// Fuerza atacante: 1.0 es la media. `nil` si el equipo no ha jugado.
        func attack(_ team: String) -> Double? {
            guard let g = games[team], g > 0, perTeamAvg > 0 else { return nil }
            return (Double(gf[team] ?? 0) / Double(g)) / perTeamAvg
        }

        /// Fuerza defensiva: por encima de 1.0 encaja más de lo normal.
        func defense(_ team: String) -> Double? {
            guard let g = games[team], g > 0, perTeamAvg > 0 else { return nil }
            return (Double(ga[team] ?? 0) / Double(g)) / perTeamAvg
        }
    }

    private static func agregar(_ matchDays: [MatchDay]) -> Tasas {
        var t = Tasas()
        for day in matchDays {
            for m in day.games where m.done {
                guard let local = m.homeScore, let visitante = m.awayScore else { continue }
                t.gf[m.home, default: 0] += local
                t.ga[m.home, default: 0] += visitante
                t.gf[m.away, default: 0] += visitante
                t.ga[m.away, default: 0] += local
                t.games[m.home, default: 0] += 1
                t.games[m.away, default: 0] += 1
                t.homeGoals += local
                t.awayGoals += visitante
                t.matches += 1
            }
        }
        return t
    }

    // MARK: Desglose

    private static func desglose(match: Match, matchDays: [MatchDay], tasas: Tasas,
                                 lambdaLocal: Double, lambdaVisitante: Double) -> [PredictionFactor] {
        let puestos = clasificacion(matchDays)

        return [
            PredictionFactor(
                labelKey: "prediction.form",
                homeValue: forma(match.home, matchDays: matchDays),
                awayValue: forma(match.away, matchDays: matchDays)
            ),
            PredictionFactor(
                labelKey: "prediction.goalsFor",
                homeValue: porPartido(tasas.gf[match.home], partidos: tasas.games[match.home]),
                awayValue: porPartido(tasas.gf[match.away], partidos: tasas.games[match.away])
            ),
            PredictionFactor(
                labelKey: "prediction.goalsAgainst",
                homeValue: porPartido(tasas.ga[match.home], partidos: tasas.games[match.home]),
                awayValue: porPartido(tasas.ga[match.away], partidos: tasas.games[match.away])
            ),
            PredictionFactor(
                labelKey: "prediction.position",
                homeValue: puestos[match.home].map { "\($0)º" } ?? "—",
                awayValue: puestos[match.away].map { "\($0)º" } ?? "—"
            ),
            PredictionFactor(
                labelKey: "prediction.expectedGoals",
                homeValue: String(format: "%.1f", lambdaLocal),
                awayValue: String(format: "%.1f", lambdaVisitante)
            ),
        ]
    }

    /// Últimos cinco resultados, del más antiguo al más reciente.
    private static func forma(_ team: String, matchDays: [MatchDay]) -> String {
        let jugados = matchDays
            .flatMap { day in
                day.games
                    .filter { ($0.home == team || $0.away == team) && $0.done }
                    .map { (date: day.date, match: $0) }
            }
            .sorted { $0.date < $1.date }
            .suffix(5)

        guard !jugados.isEmpty else { return "—" }

        return jugados.map { item -> String in
            let m = item.match
            guard let local = m.homeScore, let visitante = m.awayScore else { return "·" }
            let propios = m.home == team ? local : visitante
            let ajenos = m.home == team ? visitante : local
            if propios > ajenos { return String(localized: "form.win.initial") }
            if propios < ajenos { return String(localized: "form.loss.initial") }
            return String(localized: "form.draw.initial")
        }.joined(separator: " ")
    }

    private static func porPartido(_ goles: Int?, partidos: Int?) -> String {
        guard let partidos, partidos > 0 else { return "—" }
        return String(format: "%.1f", Double(goles ?? 0) / Double(partidos))
    }

    /// Puesto de cada equipo en la fase liga por puntos, diferencia y goles.
    private static func clasificacion(_ matchDays: [MatchDay]) -> [String: Int] {
        struct Fila { var pts = 0, dg = 0, gf = 0 }
        var filas: [String: Fila] = [:]

        for day in matchDays {
            for m in day.games where m.done && m.stage == .league {
                guard let local = m.homeScore, let visitante = m.awayScore else { continue }
                var casa = filas[m.home] ?? Fila()
                var fuera = filas[m.away] ?? Fila()
                casa.gf += local; casa.dg += local - visitante
                fuera.gf += visitante; fuera.dg += visitante - local
                if local > visitante { casa.pts += 3 }
                else if local < visitante { fuera.pts += 3 }
                else { casa.pts += 1; fuera.pts += 1 }
                filas[m.home] = casa
                filas[m.away] = fuera
            }
        }

        let ordenadas = filas.sorted {
            if $0.value.pts != $1.value.pts { return $0.value.pts > $1.value.pts }
            if $0.value.dg != $1.value.dg { return $0.value.dg > $1.value.dg }
            return $0.value.gf > $1.value.gf
        }
        return Dictionary(uniqueKeysWithValues:
            ordenadas.enumerated().map { ($0.element.key, $0.offset + 1) })
    }

    // MARK: Poisson

    /// Probabilidad de exactamente `k` goles con media `lambda`.
    ///
    /// Se calcula multiplicando en vez de con factoriales: `k` no pasa de ocho
    /// y así no hay desbordamiento ni pérdida de precisión.
    private static func poisson(_ k: Int, _ lambda: Double) -> Double {
        var resultado = exp(-lambda)
        guard k > 0 else { return resultado }
        for i in 1...k { resultado *= lambda / Double(i) }
        return resultado
    }
}
