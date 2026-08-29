//
//  TopScorersSheet.swift
//  Champions
//
//  Goleadores y asistentes del torneo, en dos pestañas.
//

import SwiftUI

struct TopScorersSheet: View {

    let scorers: [TopScorer]
    let assists: [TopScorer]

    @State private var tab: Tab = .goals
    @Environment(\.dismiss) private var dismiss
    @Environment(HighlightSettings.self) private var highlights

    enum Tab: String, CaseIterable, Identifiable {
        case goals, assists
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .goals:   return "scorers.goals"
            case .assists: return "scorers.assists"
            }
        }
    }

    private var rows: [TopScorer] { tab == .goals ? scorers : assists }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("scorers.title", selection: $tab) {
                    ForEach(Tab.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if rows.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                ScorerRow(
                                    rank: index + 1,
                                    scorer: row,
                                    unit: tab,
                                    highlight: highlights.highlight(for: row.team)
                                )
                                if index < rows.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.05))
                                        .padding(.leading, 52)
                                }
                            }
                            Spacer(minLength: 24)
                        }
                    }
                }
            }
            .background(Palette.background)
            .navigationTitle("scorers.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "soccerball")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.2))
            Text("scorers.empty")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Fila

private struct ScorerRow: View {
    let rank: Int
    let scorer: TopScorer
    let unit: TopScorersSheet.Tab
    let highlight: TeamHighlight?

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(rank)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(rank <= 3 ? Palette.gold : .white.opacity(0.4))
                .monospacedDigit()
                .frame(width: 22, alignment: .trailing)

            TeamLogoView(teamName: scorer.team, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: scorer.player)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(verbatim: Teams.name(scorer.team))
                    .font(.system(size: 11))
                    .foregroundStyle(highlight?.color ?? .white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(verbatim: "\(scorer.goals)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                // Solo tiene sentido en goles: en asistencias no hay penaltis.
                if unit == .goals, let penalties = scorer.penalties, penalties > 0 {
                    Text(String(format: String(localized: "scorers.penalties"), penalties))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(highlight?.color.opacity(0.1) ?? .clear)
    }
}
