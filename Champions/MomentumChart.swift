//
//  MomentumChart.swift
//  Champions
//
//  Quién apretaba en cada momento del partido: barras hacia arriba cuando
//  presiona el local, hacia abajo cuando presiona el visitante, y los goles
//  encima como hitos que la explican.
//
//  Es la gráfica de la app de La Liga, con sus arreglos —el eje fijo al partido
//  entero, los goles en el descuento, los goles seguidos que se tapaban, los dos
//  equipos del mismo color—, dibujada con la paleta y los escudos de esta app.
//

import SwiftUI
import Charts

/// Un punto del momentum de SofaScore.
struct MomentumPoint: Identifiable, Hashable, Sendable {
    /// Minuto del partido. Es decimal: SofaScore cierra la gráfica en el 90,5.
    let minute: Double
    /// Positivo, presión del local; negativo, del visitante.
    let value: Double
    var id: Double { minute }
}

struct MomentumChart: View {

    let points: [MomentumPoint]
    let match: Match

    @Environment(HighlightSettings.self) private var highlights

    var body: some View {
        let (homeColor, awayColor) = colors
        let marks = goalMarks
        let maxValue = max(points.map { abs($0.value) }.max() ?? 1, 1)
        // El eje es siempre el partido entero y se va rellenando, en vez de
        // encogerse al minuto actual: con el eje ajustado a los datos, en el
        // minuto 13 las barras llenaban la pantalla y se iban apretando según
        // avanzaba el partido. Solo pasa del 90 si hay algo que pintar ahí,
        // como un gol en el descuento.
        let lastMinute = max(90, points.map(\.minute).max() ?? 90, marks.map(\.x).max() ?? 90)

        VStack(spacing: 4) {
            teamLabel(match.home)

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("minute", point.minute),
                        y: .value("pressure", point.value)
                    )
                    .foregroundStyle(point.value >= 0 ? homeColor : awayColor)
                }

                RuleMark(y: .value("zero", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.white.opacity(0.18))

                // Los balones van dentro del área de dibujo, en la franja que
                // deja libre el margen del eje vertical. Como en la app de La
                // Liga —colgados por fuera del área—, el de un gol del
                // visitante tapaba la etiqueta del minuto del eje de abajo.
                ForEach(marks) { mark in
                    PointMark(
                        x: .value("minute", mark.x),
                        y: .value("pressure", mark.isHome ? maxValue * 1.15 : -maxValue * 1.15)
                    )
                    .symbolSize(0)
                    .annotation(position: .overlay) {
                        // En propia meta el balón va invertido y del color del
                        // suceso: está del lado de quien se apunta el tanto, y
                        // sin distintivo parecería suyo.
                        Image(systemName: mark.isOwnGoal
                              ? MatchEventType.ownGoal.symbolName
                              : MatchEventType.goal.symbolName)
                            .font(.system(size: 11))
                            .foregroundStyle(mark.isOwnGoal ? MatchEventType.ownGoal.tint : .white)
                    }
                }
            }
            .chartYScale(domain: -maxValue * 1.3 ... maxValue * 1.3)
            // Cuatro minutos de margen: con uno y medio, la etiqueta del 90
            // quedaba medio cortada contra el borde derecho.
            .chartXScale(domain: 0 ... (lastMinute + 4))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [15.0, 30.0, 45.0, 60.0, 75.0, 90.0]) { value in
                    AxisValueLabel {
                        if let minute = value.as(Double.self) {
                            // Tamaño natural: la del 90, pegada al borde,
                            // salía truncada como «9…».
                            Text(verbatim: "\(Int(minute))'")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .fixedSize()
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                        .foregroundStyle(Color.white.opacity(0.08))
                }
            }
            .frame(height: 150)

            teamLabel(match.away)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("detail.momentum"))
    }

    private func teamLabel(_ team: String) -> some View {
        HStack(spacing: 6) {
            TeamLogoView(teamName: team, size: 14)
            Text(verbatim: Teams.name(team))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(highlights.highlight(for: team)?.color ?? Color.white.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: Colores

    /// Colores de las dos mitades. Manda el color resaltado de cada equipo, y
    /// si no hay, el del club. En la app de La Liga el Espanyol–Real Madrid
    /// salía entero en naranja y no se veía quién apretaba: si los dos quedan
    /// parecidos, el visitante pasa a un gris azulado.
    private var colors: (Color, Color) {
        let home = highlights.highlight(for: match.home)?.color ?? Teams.color(match.home)
        var away = highlights.highlight(for: match.away)?.color ?? Teams.color(match.away)
        if Self.lookAlike(home, away) { away = Color(hex: 0x4A5568) }
        return (home, away)
    }

    private static func lookAlike(_ a: Color, _ b: Color) -> Bool {
        let ca = UIColor(a).cgColor.components ?? []
        let cb = UIColor(b).cgColor.components ?? []
        guard ca.count >= 3, cb.count >= 3 else { return false }
        let distance = (0..<3).reduce(0.0) { $0 + abs(Double(ca[$1] - cb[$1])) }
        return distance < 0.45
    }

    // MARK: Goles

    private struct GoalMark: Identifiable {
        let id: String
        /// Posición en el eje: minuto más descuento, desplazado si hace falta
        /// para no tapar al gol anterior del mismo lado.
        let x: Double
        let isHome: Bool
        let isOwnGoal: Bool
    }

    /// Los goles del partido, sacados de sus sucesos. Un gol en propia meta va
    /// del lado del equipo que se apunta el tanto, que es como se lee un
    /// marcador.
    private var goalMarks: [GoalMark] {
        let goals = (match.details?.events ?? []).filter(\.type.isGoal)

        // El balón es una indicación, no una medida —el minuto exacto está en la
        // cronología de debajo—, así que se le deja moverse lo justo para que dos
        // goles seguidos no se tapen: un minuto son unos nueve píxeles y el balón
        // ocupa más de veinte. Arriba y abajo no se estorban entre sí.
        let minimumGap = 3.5
        var lastTop = -Double.infinity
        var lastBottom = -Double.infinity

        return goals
            .map { event -> (MatchEvent, Double, Bool) in
                // El descuento cuenta: un gol en el 90+4 va en el 94. Sin esto,
                // los goles del añadido caían encima del 90 o fuera del eje.
                let minute = Double(event.minute + (event.extraTime ?? 0))
                let byHome = event.teamName == match.home
                let forHome = event.type == .ownGoal ? !byHome : byHome
                return (event, minute, forHome)
            }
            .sorted { $0.1 < $1.1 }
            .map { event, minute, top in
                var x = minute
                if top {
                    x = max(x, lastTop + minimumGap)
                    lastTop = x
                } else {
                    x = max(x, lastBottom + minimumGap)
                    lastBottom = x
                }
                return GoalMark(id: event.id, x: x, isHome: top, isOwnGoal: event.type == .ownGoal)
            }
    }
}
