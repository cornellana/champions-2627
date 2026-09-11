//
//  PlayerStatsSheet.swift
//  Champions
//
//  Ficha de un jugador: lo que hizo en el partido desde el que se abre, su media
//  por partido y el total en la Champions de esta temporada.
//
//  Es la de la app de La Liga, con la misma tabla de tres columnas —Partido,
//  Media y Total— y los mismos grupos. Cambian tres cosas: los textos pasan por
//  el catálogo de idiomas, los números se formatean con el idioma de la app, y
//  de dónde sale cada dato vive aparte, en `PlayerStatsService`.
//

import SwiftUI

// MARK: - Tabla

/// Un valor de la tabla, sin formatear. Se formatea al dibujarlo, con el
/// idioma del entorno, para que el separador de miles sea el de cada idioma.
private enum PlayerStatValue {
    case count(Double)
    case decimal(Double)
    /// De 0 a 100.
    case percent(Double)
}

private struct PlayerStatRow: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let match: PlayerStatValue?
    let average: PlayerStatValue?
    let total: PlayerStatValue?
}

private struct PlayerStatGroup: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let rows: [PlayerStatRow]
}

// MARK: - PlayerStatsSheet

struct PlayerStatsSheet: View {

    let selection: PlayerSelection
    var season: AppSeason = .current
    /// Calendario completo. Sirve para encontrar a un jugador que llega sin
    /// identificador de ESPN, como los de la lista de goleadores.
    var matchDays: [MatchDay] = []

    @Environment(\.dismiss) private var dismiss

    @State private var groups: [PlayerStatGroup] = []
    @State private var isLoading = true
    @State private var hasMatchData = false
    @State private var age: Int?
    @State private var espnPosition: String?
    @State private var sofaScoreID: Int?
    @State private var marketValue: Int?

    private let matchWidth: CGFloat = 58
    private let averageWidth: CGFloat = 58
    private let totalWidth: CGFloat = 64

    /// La columna del partido lleva el color de su fase, como el resto de la app.
    private var matchAccent: Color { selection.match?.stage.accent ?? Palette.silver }

    private static let valueGreen = Color(hex: 0x1B8A4C)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if isLoading {
                        loadingView
                    } else if groups.isEmpty {
                        noDataView
                    } else {
                        table
                    }
                    Spacer(minLength: 40)
                }
            }
            .background(Palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("player.title")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(verbatim: "Champions \(season.displayName)")
                            .font(.caption2)
                            .foregroundStyle(Palette.silver.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: Cabecera

    private var header: some View {
        HStack(spacing: 12) {
            photo

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: selection.playerName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let team = selection.teamName, !team.isEmpty {
                    Text(verbatim: Teams.name(team))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }

                HStack(spacing: 6) {
                    // El de la alineación va primero porque es el de ese
                    // partido; si no se entiende, manda el de ESPN.
                    if let position = Self.positionKey(selection.position) ?? Self.positionKey(espnPosition) {
                        Text(position)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    if let age {
                        Text("player.age \(age)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
            }

            Spacer(minLength: 8)

            if let marketValue {
                VStack(spacing: 2) {
                    Text("player.value")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                    Text(verbatim: Self.marketValueText(marketValue))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Self.valueGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Self.valueGreen.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.sectionHeader)
    }

    @ViewBuilder
    private var photo: some View {
        if let id = sofaScoreID,
           let url = URL(string: "https://api.sofascore.app/api/v1/player/\(id)/image") {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                } else {
                    photoFallback
                }
            }
            .frame(width: 56, height: 56)
        } else {
            photoFallback
        }
    }

    private var photoFallback: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.05))
            if let team = selection.teamName, !team.isEmpty {
                TeamLogoView(teamName: team, size: 32)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(width: 56, height: 56)
    }

    // MARK: Tabla

    private var table: some View {
        VStack(spacing: 0) {
            if hasMatchData, let match = selection.match {
                matchBanner(match)
            }
            columnHeader
            ForEach(groups) { group in
                VStack(spacing: 2) {
                    groupHeader(group.title)
                    ForEach(group.rows) { row($0) }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func matchBanner(_ match: Match) -> some View {
        let isHome = selection.teamName == match.home
        let opponent = isHome ? match.away : match.home
        let own = (isHome ? match.homeScore : match.awayScore) ?? 0
        let other = (isHome ? match.awayScore : match.homeScore) ?? 0

        return HStack(spacing: 8) {
            Group {
                if match.stage == .league, let matchday = match.matchday {
                    Text("player.matchday \(matchday)")
                } else {
                    Text(match.stage.shortTitle)
                }
            }
            .font(.system(size: 9, weight: .heavy))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(match.stage.accent)

            Spacer()

            Text(verbatim: "vs \(Teams.name(opponent))")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            TeamLogoView(teamName: opponent, size: 16)
            Text(verbatim: "\(own)-\(other)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Palette.dayHeader)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if hasMatchData {
                Text("player.column.match")
                    .foregroundStyle(matchAccent)
                    .frame(width: matchWidth)
            }
            Text("player.column.average")
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: averageWidth, alignment: .trailing)
            Text("player.column.total")
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: totalWidth, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .heavy))
        .textCase(.uppercase)
        .tracking(0.6)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 26)
        .padding(.vertical, 8)
    }

    private func groupHeader(_ title: LocalizedStringKey) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Palette.silver)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Palette.dayHeader)
    }

    private func row(_ row: PlayerStatRow) -> some View {
        HStack(spacing: 0) {
            Text(row.label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasMatchData {
                matchChip(row.match).frame(width: matchWidth)
            }

            text(row.average)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(row.average == nil ? .white.opacity(0.25) : .white.opacity(0.85))
                .frame(width: averageWidth, alignment: .trailing)

            text(row.total)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(row.total == nil ? .white.opacity(0.25) : .white)
                .frame(width: totalWidth, alignment: .trailing)
        }
        .monospacedDigit()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.sectionHeader))
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func matchChip(_ value: PlayerStatValue?) -> some View {
        if let value {
            text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(matchAccent.opacity(0.35)))
        } else {
            Text(verbatim: "—")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.25))
        }
    }

    private func text(_ value: PlayerStatValue?) -> Text {
        switch value {
        case .count(let v)?:   return Text(v, format: .number.precision(.fractionLength(0)))
        case .decimal(let v)?: return Text(v, format: .number.precision(.fractionLength(1)))
        case .percent(let v)?: return Text(v / 100, format: .percent.precision(.fractionLength(0)))
        case nil:              return Text(verbatim: "—")
        }
    }

    // MARK: Estados

    private var loadingView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Palette.silver).scaleEffect(1.2)
            Text("player.loading")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var noDataView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.2))
            Text("player.noData")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
            Text("player.noData.detail")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.top, 50)
    }

    // MARK: Carga

    private func load() async {
        defer { isLoading = false }

        var athleteID = selection.athleteID
        if athleteID?.isEmpty ?? true {
            athleteID = await PlayerStatsService.resolveAthleteID(
                name: selection.playerName, team: selection.teamName, matchDays: matchDays)
        }

        // ESPN y el partido de SofaScore no dependen uno del otro: a la vez.
        let id = athleteID
        async let seasonTask = PlayerStatsService.seasonStats(athleteID: id, season: season)
        async let infoTask = PlayerStatsService.athleteInfo(id: id)
        async let matchTask = PlayerStatsService.matchPlayer(for: selection, season: season)
        let (seasonStats, info, inMatch) = await (seasonTask, infoTask, matchTask)

        age = info.age
        espnPosition = info.position

        // El jugador en SofaScore sale de la alineación si se abrió desde un
        // partido; si no, del buscador.
        var sofaID = inMatch?.playerID
        if sofaID == nil {
            sofaID = await PlayerStatsService.searchPlayer(name: selection.playerName, team: selection.teamName)
        }
        sofaScoreID = sofaID

        var rating: Double?
        if let sofaID {
            async let valueTask = PlayerStatsService.marketValue(playerID: sofaID)
            async let ratingTask = PlayerStatsService.seasonRating(playerID: sofaID, season: season)
            let (value, seasonRating) = await (valueTask, ratingTask)
            marketValue = value
            rating = seasonRating
        }

        hasMatchData = selection.match?.done == true && !(inMatch?.stats.isEmpty ?? true)
        groups = buildGroups(season: seasonStats, match: inMatch?.stats ?? [:], seasonRating: rating)
    }

    // MARK: Grupos

    /// Junta el partido y la temporada en los grupos de la tabla. Un concepto
    /// sin nada ni en el partido ni en la temporada no se enseña, como en la
    /// app de La Liga: una fila de ceros solo estorba.
    private func buildGroups(season s: [String: Double], match m: [String: Double],
                             seasonRating: Double?) -> [PlayerStatGroup] {
        let appearances = s["appearances"] ?? 0
        let withMatch = hasMatchData

        /// Concepto contable: el partido, la media —total entre partidos— y el total.
        func count(_ id: String, _ label: LocalizedStringKey,
                   match matchKey: String?, season seasonKey: String?,
                   average: Bool = true) -> PlayerStatRow? {
            let inMatch = matchKey.flatMap { m[$0] } ?? 0
            let inSeason = seasonKey.flatMap { s[$0] } ?? 0
            guard inMatch > 0 || inSeason > 0 else { return nil }
            return PlayerStatRow(
                id: id, label: label,
                match: withMatch && inMatch > 0 ? .count(inMatch) : nil,
                average: average && inSeason > 0 && appearances > 0
                    ? Self.averageValue(inSeason / appearances) : nil,
                total: inSeason > 0 ? .count(inSeason) : nil)
        }

        /// Acierto en el pase: el del partido y el de la temporada, sin total.
        func passAccuracy() -> PlayerStatRow? {
            var inMatch: Double?
            if let total = m["totalPass"], let good = m["accuratePass"], total > 0 {
                inMatch = good / total * 100
            }
            // ESPN lo da unas veces como fracción y otras como porcentaje.
            let inSeason = s["passPct"].map { $0 > 1 ? $0 : $0 * 100 } ?? 0
            guard inMatch != nil || inSeason > 0 else { return nil }
            return PlayerStatRow(
                id: "passPct", label: "player.stat.passPct",
                match: withMatch ? inMatch.map { .percent($0) } : nil,
                average: inSeason > 0 ? .percent(inSeason) : nil,
                total: nil)
        }

        /// Valoración: la del partido y la media de la temporada, sin total.
        func rating() -> PlayerStatRow? {
            let inMatch = m["rating"] ?? 0
            let inSeason = seasonRating ?? 0
            guard inMatch > 0 || inSeason > 0 else { return nil }
            return PlayerStatRow(
                id: "rating", label: "player.stat.rating",
                match: withMatch && inMatch > 0 ? .decimal(inMatch) : nil,
                average: inSeason > 0 ? .decimal(inSeason) : nil,
                total: nil)
        }

        /// Dato decimal que solo existe en el partido: kilómetros, goles evitados.
        func matchOnly(_ id: String, _ label: LocalizedStringKey, _ key: String) -> PlayerStatRow? {
            guard withMatch, let value = m[key], value > 0 else { return nil }
            return PlayerStatRow(id: id, label: label, match: .decimal(value), average: nil, total: nil)
        }

        func group(_ id: String, _ title: LocalizedStringKey, _ rows: [PlayerStatRow?]) -> PlayerStatGroup? {
            let present = rows.compactMap { $0 }
            return present.isEmpty ? nil : PlayerStatGroup(id: id, title: title, rows: present)
        }

        let all: [PlayerStatGroup?] = [
            group("general", "player.group.general", [
                count("minutes", "player.stat.minutes", match: "minutesPlayed", season: "minutes"),
                rating(),
                count("appearances", "player.stat.appearances", match: nil, season: "appearances", average: false),
                count("starts", "player.stat.starts", match: nil, season: "starts", average: false),
            ]),
            group("attack", "player.group.attack", [
                count("goals", "player.stat.goals", match: "goals", season: "totalGoals"),
                count("assists", "player.stat.assists", match: "goalAssist", season: "goalAssists"),
                count("shots", "player.stat.shots", match: "totalShots", season: "totalShots"),
                count("onTarget", "player.stat.onTarget", match: "onTargetScoringAttempt", season: "shotsOnTarget"),
                count("keyPasses", "player.stat.keyPasses", match: "keyPass", season: nil, average: false),
                count("bigChances", "player.stat.bigChances", match: "bigChanceCreated", season: nil, average: false),
            ]),
            group("passing", "player.group.passing", [
                count("passes", "player.stat.passes", match: "totalPass", season: "totalPasses"),
                count("accuratePasses", "player.stat.accuratePasses", match: "accuratePass", season: "accuratePasses"),
                passAccuracy(),
            ]),
            group("defence", "player.group.defence", [
                count("tackles", "player.stat.tackles", match: "totalTackle", season: "totalTackles"),
                count("tacklesWon", "player.stat.tacklesWon", match: "wonTackle", season: nil, average: false),
                count("interceptions", "player.stat.interceptions", match: "interceptionWon", season: "interceptions"),
                count("clearances", "player.stat.clearances", match: "totalClearance", season: nil, average: false),
                count("recoveries", "player.stat.recoveries", match: "ballRecovery", season: nil, average: false),
                count("aerialsWon", "player.stat.aerialsWon", match: "aerialWon", season: nil, average: false),
            ]),
            group("discipline", "player.group.discipline", [
                count("fouls", "player.stat.fouls", match: "fouls", season: "foulsCommitted"),
                count("possessionLost", "player.stat.possessionLost", match: "possessionLostCtrl", season: nil, average: false),
                count("yellowCards", "player.stat.yellowCards", match: nil, season: "yellowCards", average: false),
                count("redCards", "player.stat.redCards", match: nil, season: "redCards", average: false),
            ]),
            group("physical", "player.group.physical", [
                matchOnly("distance", "player.stat.distance", "kilometersCovered"),
                count("touches", "player.stat.touches", match: "touches", season: nil, average: false),
            ]),
            group("goalkeeping", "player.group.goalkeeping", [
                count("saves", "player.stat.saves", match: "saves", season: "saves"),
                count("savesInBox", "player.stat.savesInBox", match: "savedShotsFromInsideTheBox", season: nil, average: false),
                matchOnly("goalsPrevented", "player.stat.goalsPrevented", "goalsPrevented"),
                count("cleanSheets", "player.stat.cleanSheets", match: nil, season: "cleanSheet", average: false),
            ]),
        ]
        return all.compactMap { $0 }
    }

    // MARK: Formato

    /// Media por partido: entera desde 10, con un decimal por debajo.
    private static func averageValue(_ value: Double) -> PlayerStatValue {
        value >= 10 ? .count(value) : .decimal(value)
    }

    private static func marketValueText(_ value: Int) -> String {
        if value >= 1_000_000 {
            let millions = Double(value) / 1_000_000
            return millions == millions.rounded() ? "\(Int(millions))M€" : String(format: "%.1fM€", millions)
        }
        if value >= 1_000 { return "\(value / 1_000)K€" }
        return "\(value)€"
    }

    /// Puesto a partir de la abreviatura.
    ///
    /// Llega en dos formas. ESPN da el puesto (`G`, `D`, `M`, `F`); las
    /// alineaciones, en cambio, dan la casilla de la formación —`CD-R`, `AM-L`,
    /// `LB`—, de la que basta lo que va antes del guion. Los suplentes llegan
    /// como `SUB`, que no dice nada: devuelve `nil` y la ficha usa el de ESPN.
    static func positionKey(_ abbreviation: String?) -> LocalizedStringKey? {
        let code = (abbreviation ?? "").uppercased()
            .split(separator: "-").first.map(String.init) ?? ""
        switch code {
        case "G", "GK", "POR":
            return "player.position.goalkeeper"
        case "D", "DF", "CB", "LB", "RB", "CD", "WB", "LWB", "RWB", "SW", "DEF":
            return "player.position.defender"
        case "M", "MF", "CM", "DM", "AM", "LM", "RM", "CDM", "CAM", "MED":
            return "player.position.midfielder"
        case "F", "FW", "ST", "CF", "LW", "RW", "W", "SS", "ATT", "DEL":
            return "player.position.forward"
        default:
            return nil
        }
    }
}
