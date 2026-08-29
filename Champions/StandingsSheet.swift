//
//  StandingsSheet.swift
//  Champions
//
//  La tabla de la fase liga: 36 equipos en una sola clasificación.
//
//  Es la diferencia de fondo con una liga normal y con el Mundial. No hay
//  grupos: los ocho primeros pasan directos a octavos, del noveno al vigésimo
//  cuarto juegan un play-off y del vigésimo quinto en adelante se van a casa.
//

import SwiftUI

struct StandingsSheet: View {

    let standings: [LeagueStanding]
    let store: MatchStore

    @Environment(\.dismiss) private var dismiss
    @Environment(HighlightSettings.self) private var highlights

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    columnHeader
                    ForEach(standings) { row in
                        StandingRow(
                            row: row,
                            form: store.form(for: row.team),
                            highlight: highlights.highlight(for: row.team)
                        )
                        if row.id != standings.last?.id {
                            Divider()
                                .background(Color.white.opacity(0.05))
                                .padding(.leading, 46)
                        }
                        // Las dos líneas que de verdad importan del torneo.
                        if row.position == 8 || row.position == 24 {
                            cutLine(after: row.position)
                        }
                    }
                    legend
                    Spacer(minLength: 24)
                }
            }
            .background(Palette.background)
                        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("standings.title")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Cabecera de columnas

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text(verbatim: "#")
                .frame(width: 26, alignment: .center)
            Text("standings.team")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            Group {
                Text("standings.played.short").frame(width: 22)
                Text("standings.won.short").frame(width: 20)
                Text("standings.drawn.short").frame(width: 20)
                Text("standings.lost.short").frame(width: 20)
                Text("standings.goalDiff.short").frame(width: 28)
                Text("standings.points.short").frame(width: 26)
            }
        }
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white.opacity(0.4))
        .tracking(0.5)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.sectionHeader)
    }

    /// Línea de corte con el nombre de lo que hay a partir de ahí.
    private func cutLine(after position: Int) -> some View {
        let zone = StandingZone(position: position + 1)
        return HStack(spacing: 8) {
            Rectangle()
                .fill(zone.color)
                .frame(width: 20, height: 2)
            Text(zone.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(zone.color)
                .tracking(0.8)
            Rectangle()
                .fill(zone.color.opacity(0.35))
                .frame(height: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Palette.dayHeader)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(StandingZone.allCases, id: \.self) { zone in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zone.color)
                        .frame(width: 3, height: 14)
                    Text(zone.label)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text(verbatim: zone.range)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(16)
    }
}

// MARK: - Fila

private struct StandingRow: View {
    let row: LeagueStanding
    let form: [String]
    let highlight: TeamHighlight?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Puesto, con la banda de color de su zona.
                ZStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(row.zone.color)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 20)
                    Text(verbatim: "\(row.position)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .monospacedDigit()
                }
                .frame(width: 26)

                TeamLogoView(teamName: row.team, size: 22)
                    .padding(.leading, 4)

                Text(verbatim: Teams.name(row.team))
                    .font(.system(size: 13, weight: highlight != nil ? .bold : .regular))
                    .foregroundStyle(highlight?.color ?? .white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)

                Group {
                    cell("\(row.played)", width: 22)
                    cell("\(row.won)", width: 20)
                    cell("\(row.drawn)", width: 20)
                    cell("\(row.lost)", width: 20)
                    cell(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)", width: 28)
                    Text(verbatim: "\(row.points)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .frame(width: 26)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if !form.isEmpty {
                HStack(spacing: 3) {
                    Spacer()
                    ForEach(Array(form.enumerated()), id: \.offset) { _, result in
                        Text(verbatim: localizedForm(result))
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 13, height: 13)
                            .background(formColor(result))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
            }
        }
        .background(highlight?.color.opacity(0.1) ?? .clear)
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(verbatim: text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .monospacedDigit()
            .frame(width: width)
    }

    /// La inicial de victoria, empate y derrota cambia con el idioma.
    private func localizedForm(_ result: String) -> String {
        switch result {
        case "W": return String(localized: "form.win.initial")
        case "L": return String(localized: "form.loss.initial")
        default:  return String(localized: "form.draw.initial")
        }
    }

    private func formColor(_ result: String) -> Color {
        switch result {
        case "W": return Color(hex: 0x1B8A4C)
        case "L": return Color(hex: 0xC0392B)
        default:  return Color(hex: 0x6E7A96)
        }
    }
}

// MARK: - Rango de cada zona

private extension StandingZone {
    /// Puestos que abarca la zona, para la leyenda.
    var range: String {
        switch self {
        case .direct:  return "1–8"
        case .playoff: return "9–24"
        case .out:     return "25–36"
        }
    }
}
