//
//  BracketSheet.swift
//  Champions
//
//  El cuadro de las eliminatorias.
//
//  Las fases se van definiendo a medida que avanza el torneo: el play-off se
//  sortea a finales de enero y de ahí en adelante cada ronda depende de la
//  anterior. Por eso la vista no da nada por hecho — dibuja lo que hay y deja
//  anunciada la fecha de lo que todavía no se ha sorteado.
//

import SwiftUI

struct BracketSheet: View {

    let store: MatchStore
    /// Se llama al tocar un partido, para abrir su ficha.
    let onSelect: (Match) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(HighlightSettings.self) private var highlights

    private let knockoutStages: [Stage] = [.playoff, .r16, .qf, .sf, .final]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(knockoutStages) { stage in
                        Section {
                            let ties = store.ties(in: stage)
                            if ties.isEmpty {
                                pendingRow(stage)
                            } else {
                                ForEach(ties, id: \.id) { tie in
                                    TieView(legs: tie.legs, stage: stage, onSelect: onSelect)
                                }
                            }
                        } header: {
                            stageHeader(stage)
                        }
                    }
                    Spacer(minLength: 32)
                }
            }
            .background(Palette.background)
            .navigationTitle("bracket.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func stageHeader(_ stage: Stage) -> some View {
        HStack(spacing: 8) {
            if stage == .final {
                EuropeanCupView(size: 18)
            }
            Text(stage.title)
                .font(.caption.weight(.heavy))
                .foregroundStyle(stage.accent)
                .tracking(1)
            Spacer()
            Text(verbatim: stageDates(stage))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.sectionHeader)
    }

    /// Aviso de fase todavía sin sortear, con la fecha prevista si se conoce.
    private func pendingRow(_ stage: Stage) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
            Text("bracket.pending")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.05))
        }
    }

    /// Rango de fechas de la fase, sacado de los partidos que ya hay.
    private func stageDates(_ stage: Stage) -> String {
        let dates = store.matchDays
            .filter { $0.stage == stage }
            .map(\.date)
            .sorted()
        guard let first = dates.first, let last = dates.last else { return "" }
        if first == last { return MatchSectionView.shortDate(first) }
        return "\(MatchSectionView.shortDate(first)) – \(MatchSectionView.shortDate(last))"
    }
}

// MARK: - Una eliminatoria

private struct TieView: View {
    let legs: [Match]
    let stage: Stage
    let onSelect: (Match) -> Void

    @Environment(HighlightSettings.self) private var highlights

    /// Los dos equipos del cruce, tomados de la ida.
    private var teams: (home: String, away: String)? {
        guard let first = legs.first else { return nil }
        return (first.home, first.away)
    }

    /// Global de la eliminatoria.
    ///
    /// Se toma del campo `aggregate` si el script ya lo calculó; si no, se suma
    /// aquí teniendo en cuenta que en la vuelta se invierten los papeles.
    private var aggregate: (Int, Int)? {
        if let stored = legs.last?.aggregateScore { return stored }
        guard legs.count == 2, legs.allSatisfy(\.done), let teams else { return nil }
        var home = 0, away = 0
        for leg in legs {
            guard let h = leg.homeScore, let a = leg.awayScore else { return nil }
            if leg.home == teams.home { home += h; away += a } else { home += a; away += h }
        }
        return (home, away)
    }

    /// Quién pasa: por global y, si hay empate, por la tanda de penaltis.
    private var winner: String? {
        guard let teams else { return nil }
        if let shootout = legs.last?.shootoutScore, legs.last?.done == true {
            // El campo `shootout` va en el orden del partido de vuelta.
            guard let last = legs.last else { return nil }
            let localWins = shootout.0 > shootout.1
            return localWins ? last.home : last.away
        }
        guard let aggregate else { return nil }
        if aggregate.0 == aggregate.1 { return nil }
        return aggregate.0 > aggregate.1 ? teams.home : teams.away
    }

    var body: some View {
        VStack(spacing: 0) {
            if let teams {
                header(teams)
            }
            ForEach(legs) { leg in
                legRow(leg)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(leg) }
            }
        }
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.09))
        }
    }

    private func header(_ teams: (home: String, away: String)) -> some View {
        HStack(spacing: 10) {
            teamBadge(teams.home)
            Spacer(minLength: 4)
            if let aggregate {
                VStack(spacing: 1) {
                    Text(verbatim: "\(aggregate.0) – \(aggregate.1)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("bracket.aggregate")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(0.6)
                }
            } else {
                Text(verbatim: "vs")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
            }
            Spacer(minLength: 4)
            teamBadge(teams.away, trailing: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.dayHeader)
    }

    private func teamBadge(_ team: String, trailing: Bool = false) -> some View {
        HStack(spacing: 6) {
            if trailing { name(team) }
            TeamLogoView(teamName: team, size: 26)
                .opacity(winner == nil || winner == team ? 1 : 0.4)
            if !trailing { name(team) }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    private func name(_ team: String) -> some View {
        Text(verbatim: Teams.name(team))
            .font(.system(size: 12, weight: winner == team ? .bold : .regular))
            .foregroundStyle(highlights.highlight(for: team)?.color
                             ?? (winner == nil || winner == team ? .white : .white.opacity(0.5)))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func legRow(_ leg: Match) -> some View {
        HStack(spacing: 8) {
            Text(legLabel(leg))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 34, alignment: .leading)

            Text(verbatim: Teams.abbr(leg.home))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 38, alignment: .leading)

            if let h = leg.homeScore, let a = leg.awayScore {
                Text(verbatim: "\(h)–\(a)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } else {
                Text(verbatim: leg.time.isEmpty ? "—" : leg.time)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .monospacedDigit()
            }

            Text(verbatim: Teams.abbr(leg.away))
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 38, alignment: .trailing)

            Spacer(minLength: 4)

            if let live = leg.liveLabel {
                HStack(spacing: 3) {
                    Circle().fill(Palette.live).frame(width: 5, height: 5)
                    Text(live)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.live)
                }
            } else {
                Text(verbatim: MatchSectionView.shortDate(dateOf(leg)))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func legLabel(_ leg: Match) -> LocalizedStringKey {
        guard let number = leg.leg else { return "leg.single" }
        return number == 1 ? "leg.first" : "leg.second"
    }

    /// La fecha no viaja dentro del partido, sino en el día que lo contiene;
    /// aquí se busca por el identificador.
    private func dateOf(_ leg: Match) -> String {
        BracketDateIndex.shared.date(for: leg.id) ?? ""
    }
}

// MARK: - Índice de fechas

/// Índice de `id de partido → fecha`, para poder mostrar la fecha en vistas que
/// reciben partidos sueltos y no el día que los contiene.
@Observable
@MainActor
final class BracketDateIndex {
    static let shared = BracketDateIndex()
    private var index: [String: String] = [:]

    private init() {}

    /// Reconstruye el índice a partir del calendario completo.
    func rebuild(from matchDays: [MatchDay]) {
        var next: [String: String] = [:]
        for day in matchDays {
            for game in day.games { next[game.id] = day.date }
        }
        index = next
    }

    func date(for matchID: String) -> String? { index[matchID] }
}
