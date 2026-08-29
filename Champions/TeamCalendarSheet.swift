//
//  TeamCalendarSheet.swift
//  Champions
//
//  El calendario de un equipo, mes a mes, igual que en la app de La Liga:
//  se elige el club y se ve una rejilla donde cada día con partido lleva el
//  escudo del rival, si se juega en casa o fuera, y el resultado si ya se
//  disputó. Los partidos pendientes salen atenuados.
//
//  Se puede pasar de un equipo a otro deslizando, sin volver a la lista.
//

import SwiftUI

// MARK: - Tipos internos

/// Un mes de la rejilla, ya repartido en semanas de siete casillas.
private struct MonthData: Identifiable {
    let year: Int
    let month: Int
    let title: String
    /// Filas de siete; `nil` en los huecos de antes del día 1 y después del último.
    let weeks: [[DayData?]]

    var id: String { "\(year)-\(month)" }
}

/// Una casilla del mes.
private struct DayData {
    let day: Int
    let match: Match?
    let opponent: String?
    let isHome: Bool
}

// MARK: - TeamCalendarSheet

struct TeamCalendarSheet: View {

    let matchDays: [MatchDay]
    /// Se llama al tocar un partido, para abrir su ficha.
    let onSelect: (Match) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(HighlightSettings.self) private var highlights

    var body: some View {
        NavigationStack {
            teamList
                                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("calendar.title")
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

    /// Equipos marcados primero, luego el resto por nombre.
    private var teams: [String] {
        let presentes = Set(matchDays.flatMap { $0.games.flatMap { [$0.home, $0.away] } })
        let pool = presentes.isEmpty ? Set(Teams.all.map(\.key)) : presentes
        let ordenados = pool.sorted { Teams.name($0) < Teams.name($1) }
        let marcados = highlights.highlights.map(\.team).filter(pool.contains)
        return marcados + ordenados.filter { !marcados.contains($0) }
    }

    private var teamList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(teams, id: \.self) { team in
                    NavigationLink {
                        TeamCalendarPager(
                            teams: teams,
                            initialTeam: team,
                            matchDays: matchDays,
                            onSelect: { match in
                                dismiss()
                                onSelect(match)
                            }
                        )
                    } label: {
                        row(team)
                    }
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 64)
                }
            }
        }
        .background(Palette.background)
    }

    private func row(_ team: String) -> some View {
        let marca = highlights.highlight(for: team)
        return HStack(spacing: 14) {
            TeamLogoView(teamName: team, size: 30)
            Text(verbatim: Teams.name(team))
                .font(.subheadline.weight(marca != nil ? .bold : .regular))
                .foregroundStyle(marca?.color ?? .white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.22))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(marca?.color.opacity(0.10) ?? Palette.background)
    }
}

// MARK: - Paso de un equipo a otro

/// Páginas deslizables, una por equipo.
private struct TeamCalendarPager: View {

    let teams: [String]
    let matchDays: [MatchDay]
    let onSelect: (Match) -> Void

    @State private var index: Int
    @Environment(HighlightSettings.self) private var highlights

    init(teams: [String], initialTeam: String, matchDays: [MatchDay],
         onSelect: @escaping (Match) -> Void) {
        self.teams = teams
        self.matchDays = matchDays
        self.onSelect = onSelect
        _index = State(initialValue: teams.firstIndex(of: initialTeam) ?? 0)
    }

    private var current: String {
        guard teams.indices.contains(index) else { return "" }
        return teams[index]
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(teams.enumerated()), id: \.offset) { i, team in
                TeamMonths(team: team, matchDays: matchDays, onSelect: onSelect)
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Palette.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    TeamLogoView(teamName: current, size: 22)
                    Text(verbatim: Teams.name(current))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(highlights.highlight(for: current)?.color ?? .white)
                        .lineLimit(1)
                    Image(systemName: "chevron.left.chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
        }
    }
}

// MARK: - Meses de un equipo

private struct TeamMonths: View {

    let team: String
    let matchDays: [MatchDay]
    let onSelect: (Match) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                legend
                ForEach(months) { month in
                    MonthCard(month: month, onSelect: onSelect)
                }
                Spacer(minLength: 40)
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
        .background(Palette.background)
    }

    /// Qué significan el escudo y la letra de cada casilla.
    ///
    /// Hace falta porque las dos cosas hablan de equipos distintos: el escudo
    /// es el del RIVAL y la letra dice si juega en casa o fuera el equipo que
    /// se está mirando. Sin decirlo, se lee justo al revés.
    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                Text("venue.home.initial")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: 0x4A9EDF))
                Text("calendar.legend.home")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            HStack(spacing: 4) {
                Text("venue.away.initial")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Palette.gold)
                Text("calendar.legend.away")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text("calendar.legend.badge")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 8)
    }

    /// Partidos del equipo con la fecha en la que se juegan.
    private var pairs: [(date: String, match: Match)] {
        matchDays.flatMap { day in
            day.games
                .filter { $0.home == team || $0.away == team }
                .map { (day.date, $0) }
        }
    }

    /// Un `MonthData` por cada mes en el que el equipo tenga partido.
    private var months: [MonthData] {
        var vistos = Set<String>()
        var meses: [(Int, Int)] = []
        for (fecha, _) in pairs {
            let partes = fecha.split(separator: "-")
            guard partes.count >= 2, let y = Int(partes[0]), let m = Int(partes[1]) else { continue }
            if vistos.insert("\(y)-\(m)").inserted { meses.append((y, m)) }
        }
        meses.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return meses.map { build(year: $0.0, month: $0.1) }
    }

    private func build(year: Int, month: Int) -> MonthData {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // la semana empieza en lunes

        let primero = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let dias = cal.range(of: .day, in: .month, for: primero)!.count
        let hueco = (cal.component(.weekday, from: primero) - cal.firstWeekday + 7) % 7

        var porDia: [Int: Match] = [:]
        for (fecha, partido) in pairs {
            let partes = fecha.split(separator: "-")
            guard partes.count == 3,
                  let y = Int(partes[0]), let m = Int(partes[1]), let d = Int(partes[2]),
                  y == year, m == month else { continue }
            porDia[d] = partido
        }

        var casillas: [DayData?] = Array(repeating: nil, count: hueco)
        for d in 1...dias {
            if let partido = porDia[d] {
                casillas.append(DayData(
                    day: d,
                    match: partido,
                    opponent: partido.home == team ? partido.away : partido.home,
                    isHome: partido.home == team
                ))
            } else {
                casillas.append(DayData(day: d, match: nil, opponent: nil, isHome: false))
            }
        }
        while casillas.count % 7 != 0 { casillas.append(nil) }

        let semanas = stride(from: 0, to: casillas.count, by: 7).map {
            Array(casillas[$0..<($0 + 7)])
        }

        return MonthData(
            year: year,
            month: month,
            title: primero.formatted(.dateTime.month(.wide).year()).capitalizedFirst,
            weeks: semanas
        )
    }
}

// MARK: - Tarjeta de mes

private struct MonthCard: View {

    let month: MonthData
    let onSelect: (Match) -> Void

    /// Iniciales de los días de la semana en el idioma del usuario, empezando
    /// en lunes. Se sacan del calendario en vez de escribirlas a mano: en
    /// catalán, castellano e inglés no coinciden.
    private var weekdayInitials: [String] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let simbolos = cal.veryShortStandaloneWeekdaySymbols
        return (0..<7).map { simbolos[($0 + cal.firstWeekday - 1) % 7].uppercased() }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(verbatim: month.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(.horizontal, 6)

            HStack(spacing: 4) {
                ForEach(Array(weekdayInitials.enumerated()), id: \.offset) { _, inicial in
                    Text(verbatim: inicial)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(Array(month.weeks.enumerated()), id: \.offset) { _, semana in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { columna in
                        DayCell(data: semana[columna]) { partido in onSelect(partido) }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Palette.sectionHeader)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Casilla de día

private struct DayCell: View {

    let data: DayData?
    let onTap: (Match) -> Void

    private static let alto: CGFloat = 62

    var body: some View {
        Group {
            if let data {
                if let partido = data.match {
                    Button { onTap(partido) } label: { conPartido(data, partido) }
                        .buttonStyle(.plain)
                } else {
                    sinPartido(data.day)
                }
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.alto)
    }

    private func conPartido(_ data: DayData, _ partido: Match) -> some View {
        let jugado = partido.done
        return VStack(spacing: 1) {
            Text(verbatim: "\(data.day)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(jugado ? 0.65 : 0.4))

            if let rival = data.opponent {
                TeamLogoView(teamName: rival, size: 27)
                    // Atenuado mientras no se juegue: de un vistazo se ve qué
                    // queda por delante y qué está ya resuelto.
                    .opacity(jugado ? 1 : 0.35)
            }

            HStack(spacing: 3) {
                Text(data.isHome ? "venue.home.initial" : "venue.away.initial")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(data.isHome ? Color(hex: 0x4A9EDF) : Palette.gold)
                if jugado, let local = partido.homeScore, let visitante = partido.awayScore {
                    Text(verbatim: "\(local)-\(visitante)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.alto)
        .background(RoundedRectangle(cornerRadius: 7).fill(fondo(data, partido)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(String(
            format: String(localized: data.isHome ? "calendar.a11y.home" : "calendar.a11y.away"),
            data.day, Teams.name(data.opponent ?? "")
        )))
    }

    /// Verde si ganó, rojo si perdió, gris si empató, y casi nada si no se ha
    /// jugado. Es el resumen de la temporada de un vistazo.
    private func fondo(_ data: DayData, _ partido: Match) -> Color {
        guard partido.done,
              let local = partido.homeScore,
              let visitante = partido.awayScore else {
            return Color.white.opacity(0.03)
        }
        let propios = data.isHome ? local : visitante
        let ajenos = data.isHome ? visitante : local
        if propios > ajenos { return Color(hex: 0x1B8A4C).opacity(0.18) }
        if propios < ajenos { return Color(hex: 0xC0392B).opacity(0.14) }
        return Color.white.opacity(0.07)
    }

    private func sinPartido(_ dia: Int) -> some View {
        VStack {
            Text(verbatim: "\(dia)")
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.38))
                .padding(.top, 6)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.alto)
    }
}
