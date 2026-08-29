//
//  MatchDetailSheet.swift
//  Champions
//
//  Ficha de un partido: marcador, cronología de sucesos, alineaciones,
//  estadísticas de equipo y, en las eliminatorias, global y tanda de penaltis.
//

import SwiftUI

struct MatchDetailSheet: View {

    let match: Match

    @State private var tab: Tab = .summary
    @Environment(\.dismiss) private var dismiss
    @Environment(HighlightSettings.self) private var highlights

    enum Tab: String, CaseIterable, Identifiable {
        case summary, lineups, stats
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .summary: return "detail.summary"
            case .lineups: return "detail.lineups"
            case .stats:   return "detail.stats"
            }
        }
    }

    /// Pestañas con contenido. No se enseña una pestaña vacía: en un partido
    /// que no se ha jugado solo hay resumen.
    private var availableTabs: [Tab] {
        var tabs: [Tab] = [.summary]
        if match.details?.homeLineup != nil || match.details?.awayLineup != nil {
            tabs.append(.lineups)
        }
        if !(match.details?.teamStats ?? []).isEmpty {
            tabs.append(.stats)
        }
        return tabs
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    scoreboard

                    if availableTabs.count > 1 {
                        Picker("detail.section", selection: $tab) {
                            ForEach(availableTabs) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    switch tab {
                    case .summary: summarySection
                    case .lineups: lineupsSection
                    case .stats:   statsSection
                    }

                    Spacer(minLength: 32)
                }
            }
            .background(Palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(match.stage.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(match.stage.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if !availableTabs.contains(tab) { tab = .summary }
        }
    }

    // MARK: Marcador

    private var scoreboard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                teamColumn(match.home, score: match.homeScore, winner: isWinner(home: true))
                centerColumn
                teamColumn(match.away, score: match.awayScore, winner: isWinner(home: false))
            }
            .padding(.horizontal, 16)

            venueLine
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [match.stage.accent.opacity(0.22), Palette.background],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private func teamColumn(_ team: String, score: Int?, winner: Bool) -> some View {
        VStack(spacing: 8) {
            TeamLogoView(teamName: team, size: 56)
            Text(verbatim: Teams.name(team))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlights.highlight(for: team)?.color ?? .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let score {
                Text(verbatim: "\(score)")
                    .font(.system(size: 38, weight: winner ? .heavy : .regular, design: .rounded))
                    .foregroundStyle(winner ? .white : .white.opacity(0.55))
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var centerColumn: some View {
        VStack(spacing: 6) {
            if match.homeScore == nil {
                Text(verbatim: match.time.isEmpty ? "—" : match.time)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } else {
                Text(verbatim: "–")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.3))
            }

            if let live = match.liveLabel {
                HStack(spacing: 4) {
                    Circle().fill(Palette.live).frame(width: 6, height: 6)
                    Text(live)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.live)
                }
            } else if match.done {
                Text("match.final")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }

            if let shootout = match.shootoutScore {
                Text(String(format: String(localized: "detail.shootout"), shootout.0, shootout.1))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.gold)
                    .multilineTextAlignment(.center)
            }

            if let aggregate = match.aggregateScore {
                Text(String(format: String(localized: "detail.aggregate"), aggregate.0, aggregate.1))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 76)
        .padding(.top, 18)
    }

    private var venueLine: some View {
        VStack(spacing: 3) {
            if let stadium = match.stadium {
                Text(verbatim: stadium)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            if let city = match.venueCity {
                Text(verbatim: city)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            if let leg = match.leg {
                Text(leg == 1 ? "leg.first.long" : "leg.second.long")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(match.stage.accent)
                    .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func isWinner(home: Bool) -> Bool {
        guard match.done, let h = match.homeScore, let a = match.awayScore else { return false }
        return home ? h > a : a > h
    }

    // MARK: Resumen

    @ViewBuilder
    private var summarySection: some View {
        let events = (match.details?.events ?? []).sorted {
            ($0.minute, $0.extraTime ?? 0) < ($1.minute, $1.extraTime ?? 0)
        }

        if events.isEmpty {
            placeholder(
                icon: match.done ? "clock.badge.questionmark" : "calendar",
                text: match.done ? "detail.noEvents" : "detail.notPlayed"
            )
        } else {
            VStack(spacing: 0) {
                sectionTitle("detail.timeline")
                ForEach(events) { event in
                    EventRow(event: event, isHome: event.teamName == match.home)
                }
            }
        }

        if let penalties = match.details?.penalties, !penalties.isEmpty {
            VStack(spacing: 0) {
                sectionTitle("detail.penalties")
                PenaltyShootoutView(kicks: penalties, home: match.home, away: match.away)
            }
        }
    }

    // MARK: Alineaciones

    @ViewBuilder
    private var lineupsSection: some View {
        VStack(spacing: 0) {
            if let home = match.details?.homeLineup {
                LineupView(team: match.home, lineup: home)
            }
            if let away = match.details?.awayLineup {
                LineupView(team: match.away, lineup: away)
            }
        }
    }

    // MARK: Estadísticas

    @ViewBuilder
    private var statsSection: some View {
        let stats = match.details?.teamStats ?? []
        if stats.isEmpty {
            placeholder(icon: "chart.bar", text: "detail.noStats")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text(verbatim: Teams.abbr(match.home))
                    Spacer()
                    Text(verbatim: Teams.abbr(match.away))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Palette.sectionHeader)

                ForEach(stats) { stat in
                    StatRow(stat: stat, homeColor: Teams.color(match.home), awayColor: Teams.color(match.away))
                }
            }
        }
    }

    // MARK: Piezas comunes

    private func sectionTitle(_ key: LocalizedStringKey) -> some View {
        HStack {
            Text(key)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Palette.sectionHeader)
    }

    private func placeholder(icon: String, text: LocalizedStringKey) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.18))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
        .padding(.horizontal, 40)
    }
}

// MARK: - Suceso

private struct EventRow: View {
    let event: MatchEvent
    let isHome: Bool

    var body: some View {
        HStack(spacing: 0) {
            if !isHome { Spacer(minLength: 0) }

            HStack(spacing: 8) {
                if isHome { icon; texts } else { texts; icon }
            }
            .frame(maxWidth: .infinity, alignment: isHome ? .leading : .trailing)

            if isHome { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.04)).padding(.horizontal, 16)
        }
    }

    private var icon: some View {
        Image(systemName: event.type.symbolName)
            .font(.system(size: 13))
            .foregroundStyle(event.type.tint)
            .frame(width: 20)
    }

    private var texts: some View {
        VStack(alignment: isHome ? .leading : .trailing, spacing: 1) {
            HStack(spacing: 6) {
                if !isHome { minuteLabel }
                Text(verbatim: event.playerName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if isHome { minuteLabel }
            }
            if let related = event.relatedPlayer, !related.isEmpty {
                Text(verbatim: related)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
        }
    }

    private var minuteLabel: some View {
        Text(verbatim: event.displayMinute)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.5))
            .monospacedDigit()
    }
}

// MARK: - Alineación

private struct LineupView: View {
    let team: String
    let lineup: TeamLineup

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TeamLogoView(teamName: team, size: 22)
                Text(verbatim: Teams.name(team))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                if let formation = lineup.formation, formation != "?" {
                    Text(verbatim: formation)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.gold)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Palette.sectionHeader)

            ForEach(lineup.starters) { player in
                PlayerRow(player: player)
            }

            if !lineup.substitutes.isEmpty {
                HStack {
                    Text("lineup.substitutes")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(0.8)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Palette.dayHeader)

                ForEach(lineup.substitutes) { player in
                    PlayerRow(player: player)
                }
            }
        }
    }
}

private struct PlayerRow: View {
    let player: LineupPlayer

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: player.jersey.map(String.init) ?? "–")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)

            Text(verbatim: player.name)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)

            if let position = player.position, position != "?" {
                Text(verbatim: position)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                ForEach(player.events ?? []) { event in
                    HStack(spacing: 2) {
                        Image(systemName: event.type.symbolName)
                            .font(.system(size: 9))
                            .foregroundStyle(event.type.tint)
                        Text(verbatim: event.displayMinute)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.45))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.03)).padding(.leading, 46)
        }
    }
}

// MARK: - Estadística de equipo

private struct StatRow: View {
    let stat: TeamStat
    let homeColor: Color
    let awayColor: Color

    /// Proporción del valor local sobre el total, para la barra.
    /// Cuando los valores no son numéricos la barra se reparte a medias.
    private var ratio: Double {
        let home = Double(stat.home.filter { $0.isNumber || $0 == "." }) ?? 0
        let away = Double(stat.away.filter { $0.isNumber || $0 == "." }) ?? 0
        guard home + away > 0 else { return 0.5 }
        return home / (home + away)
    }

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(verbatim: stat.home)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Spacer()
                Text(stat.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(verbatim: stat.away)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(homeColor)
                        .frame(width: max(2, geo.size.width * ratio - 1))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(awayColor)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

// MARK: - Tanda de penaltis

private struct PenaltyShootoutView: View {
    let kicks: [PenaltyKick]
    let home: String
    let away: String

    var body: some View {
        VStack(spacing: 0) {
            row(for: home)
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 16)
            row(for: away)
        }
    }

    private func row(for team: String) -> some View {
        let own = kicks.filter { $0.team == team }.sorted { $0.order < $1.order }
        return HStack(spacing: 8) {
            TeamLogoView(teamName: team, size: 20)
            Text(verbatim: Teams.abbr(team))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 38, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(own) { kick in
                    VStack(spacing: 2) {
                        Image(systemName: kick.scored ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(kick.scored ? Color(hex: 0x2FA36B) : Color(hex: 0xC0392B))
                        Text(verbatim: shortName(kick.player))
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    .frame(width: 46)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    /// Apellido del jugador: en una fila de cinco lanzadores no cabe más.
    private func shortName(_ full: String) -> String {
        full.split(separator: " ").last.map(String.init) ?? full
    }
}
