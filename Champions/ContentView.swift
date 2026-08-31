//
//  ContentView.swift
//  Champions
//
//  Pantalla principal: el calendario del torneo agrupado por jornada en la fase
//  liga y por eliminatoria en el cuadro, con filtros de equipo y de fase.
//
//  Mantiene el formato de la app de La Liga —lista oscura, cabecera de sección,
//  fila de partido con escudos y marcador— adaptado a un torneo que cambia de
//  formato a mitad de temporada.
//

import SwiftUI

// MARK: - Colores de la app

enum Palette {
    /// Fondo general: azul noche, el del fútbol de mitad de semana.
    static let background = Color(hex: 0x080B16)
    /// Fondo de la cabecera de cada sección.
    static let sectionHeader = Color(hex: 0x101527)
    /// Fondo de la cabecera de cada día.
    static let dayHeader = Color(hex: 0x0B0F1D)
    /// Acento de la competición: el plateado de la copa.
    static let silver = Color(hex: 0xC9D2E0)
    /// Acento cálido para lo destacado.
    static let gold = Color(hex: 0xD4A03C)
    /// Verde del directo.
    static let live = Color(hex: 0x30D158)
}

// MARK: - MatchItem

/// Envoltorio para presentar la ficha con `.sheet(item:)`.
struct MatchItem: Identifiable, Equatable {
    var id: String { match.id }
    let match: Match

    static func == (lhs: MatchItem, rhs: MatchItem) -> Bool { lhs.id == rhs.id }
}

// MARK: - Sección de la lista

/// Un bloque de la lista: una jornada de la fase liga, o una fase eliminatoria.
struct MatchSection: Identifiable {
    let id: String
    let stage: Stage
    /// Jornada 1-8, solo en la fase liga.
    let matchday: Int?
    let days: [MatchDay]

    var allGames: [Match] { days.flatMap(\.games) }
}

// MARK: - ContentView

struct ContentView: View {

    @State private var store = MatchStore()
    @State private var highlights = HighlightSettings()
    @State private var language = LanguagePreference.shared

    @State private var filterTeam: String?
    @State private var filterStage: Stage?
    @State private var filterMatchday: Int?

    @State private var selectedMatch: MatchItem?
    @State private var showingStandings = false
    @State private var showingScorers = false
    @State private var showingBracket = false
    @State private var showingCalendar = false
    @State private var showingSettings = false

    /// Sección en la que se sitúa la lista. Se fija al abrir para caer en la
    /// jornada en curso; después la mueve el usuario al desplazarse.
    @State private var listAnchor: String?

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if store.isLoading && store.matchDays.isEmpty {
                            loadingView
                        } else if sections.isEmpty {
                            emptyView
                        } else {
                            ForEach(sections) { section in
                                MatchSectionView(section: section) { match in
                                    selectedMatch = MatchItem(match: match)
                                }
                                .id(section.id)
                            }
                        }
                        Spacer(minLength: 80)
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                // Posicionar por estado y no con un `scrollTo` tras un
                // temporizador: al abrir, la lista se reconstruye cuando llegan
                // los datos y se lleva por delante cualquier desplazamiento.
                .scrollPosition(id: $listAnchor, anchor: .top)
                .refreshable { await store.refresh() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    await store.refresh()
                    BracketDateIndex.shared.rebuild(from: store.matchDays)
                    await settleOnCurrentSection()
                    await NotificationService.shared.rescheduleKickoffReminders(
                        matchDays: store.matchDays,
                        teams: highlights.highlights.map(\.team),
                        prefs: highlights.notifications
                    )
                }
                .task(id: LiveRefresh(phase: scenePhase, interval: liveRefreshInterval)) {
                    // Sin este bucle los goles no entran solos con la app
                    // abierta. Solo vive mientras hay fútbol y la app está
                    // delante: fuera de esas horas no gasta batería ni datos.
                    guard scenePhase == .active, let interval = liveRefreshInterval else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: interval)
                        if Task.isCancelled { break }
                        await store.refresh()
                    }
                }
                .onChange(of: store.matchDays.count) { before, after in
                    // En una instalación limpia la lista está vacía al abrir,
                    // así que colocarla entonces no sirve de nada. Se reintenta
                    // en cuanto llegan los partidos.
                    guard before == 0, after > 0 else { return }
                    Task { await settleOnCurrentSection() }
                }
                .onChange(of: filterTeam) { _, _ in scrollToCurrentIfUnfiltered(proxy) }
                .onChange(of: filterStage) { _, _ in scrollToFirstSection(proxy) }
                .onChange(of: filterMatchday) { _, new in
                    guard let new else { return scrollToCurrentIfUnfiltered(proxy) }
                    scroll(to: "league-\(new)", proxy: proxy)
                }
                .onChange(of: selectedMatch) { _, item in
                    guard item == nil else { return }
                    scrollToCurrentIfUnfiltered(proxy)
                }
            }
            .background(Palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .top, spacing: 0) {
                FilterBar(
                    filterTeam: $filterTeam,
                    filterStage: $filterStage,
                    filterMatchday: $filterMatchday,
                    teams: orderedTeams,
                    stages: store.availableStages,
                    matchdays: store.availableMatchdays,
                    highlightColor: filterTeam.flatMap { highlights.highlight(for: $0)?.color }
                )
            }
        }
        .environment(highlights)
        .sheet(item: $selectedMatch) { item in
            // El partido se vuelve a buscar en el store en cada repintado: con
            // la copia guardada al pulsar, la ficha se quedaría congelada en el
            // marcador de ese instante mientras la lista de detrás se actualiza.
            let live = store.allMatches.first { $0.id == item.match.id } ?? item.match
            MatchDetailSheet(match: live, matchDays: store.matchDays)
                .environment(highlights)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingStandings) {
            StandingsSheet(standings: store.standings, store: store)
                .environment(highlights)
        }
        .sheet(isPresented: $showingScorers) {
            TopScorersSheet(scorers: store.topScorers, assists: store.topAssists)
                .environment(highlights)
        }
        .sheet(isPresented: $showingCalendar) {
            TeamCalendarSheet(matchDays: store.matchDays) { match in
                selectedMatch = MatchItem(match: match)
            }
            .environment(highlights)
        }
        .sheet(isPresented: $showingBracket) {
            BracketSheet(store: store) { match in
                showingBracket = false
                selectedMatch = MatchItem(match: match)
            }
            .environment(highlights)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(settings: highlights, store: store, language: language)
                .environment(highlights)
        }
        .preferredColorScheme(.dark)
        // El idioma elegido a mano manda sobre el del teléfono. Va en la raíz
        // para que lo hereden también las hojas.
        .environment(\.locale, language.selected.locale ?? Locale.autoupdatingCurrent)
    }

    // MARK: Barra de herramientas

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 10) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("a11y.settings")

                if store.isLoading {
                    ProgressView().tint(Palette.gold).scaleEffect(0.8)
                }
            }
            .foregroundStyle(.white)
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text("app.title.short")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize()
                Text(String(format: String(localized: "app.season"),
                            store.selectedSeason.displayName))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.gold)
                staleWarning
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 11) {
                Button { showingCalendar = true } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("a11y.calendar")

                Button { showingBracket = true } label: {
                    Image(systemName: "trophy")
                }
                .accessibilityLabel("a11y.bracket")

                Button { showingScorers = true } label: {
                    Image(systemName: "soccerball")
                }
                .accessibilityLabel("a11y.scorers")

                Button { showingStandings = true } label: {
                    Image(systemName: "list.number")
                }
                .accessibilityLabel("a11y.standings")
            }
            .foregroundStyle(.white)
        }
    }

    // MARK: Frescura de los datos

    /// Aviso de que los datos no están al día.
    ///
    /// Solo sale cuando hay algo que decir. Mientras todo va bien no se enseña
    /// nada: una etiqueta permanente se vuelve ruido y deja de leerse justo el
    /// día que importa.
    @ViewBuilder
    private var staleWarning: some View {
        if let aviso = staleText {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7))
                Text(aviso)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Color(hex: 0xE8A33C))
        }
    }

    private var staleText: LocalizedStringKey? {
        // Un fallo del último intento se dice siempre, aunque el dato sea
        // reciente: significa que ha dejado de llegar.
        if store.lastRefreshFailed {
            guard let marca = store.lastUpdated else { return "stale.unknown" }
            return LocalizedStringKey(String(
                format: String(localized: "stale.since"),
                marca.formatted(date: .omitted, time: .shortened)))
        }
        // Sin fallo, la antigüedad solo importa con el balón rodando: en
        // reposo el actualizador publica cada diez minutos y avisar de eso
        // sería dar la alarma cada diez minutos sin que pase nada.
        guard store.allMatches.contains(where: \.isLive),
              let edad = store.dataAge, edad > 180 else { return nil }
        let minutos = Int(edad / 60)
        if minutos < 60 {
            return LocalizedStringKey(String(
                format: String(localized: "stale.minutes"), minutos))
        }
        return LocalizedStringKey(String(
            format: String(localized: "stale.hours"), minutos / 60))
    }

    // MARK: Refresco automático

    /// Identidad del bucle de refresco: al cambiar, SwiftUI lo reinicia con la
    /// cadencia nueva; al quedarse en `nil` el intervalo, lo cancela.
    private struct LiveRefresh: Equatable {
        let phase: ScenePhase
        let interval: Duration?
    }

    /// Cada cuánto refrescar solo, o `nil` si no hay nada que seguir.
    ///
    /// Tres ritmos. El de la ventana del saque hace falta porque el estado "en
    /// juego" solo aparece si alguien ha refrescado antes: sin él, una app
    /// abierta desde media hora antes no se enteraría de que ha empezado.
    private var liveRefreshInterval: Duration? {
        if store.allMatches.contains(where: \.isLive) { return .seconds(45) }
        if kickoffWithin(before: 900, after: 900) { return .seconds(60) }
        if kickoffWithin(before: 3600, after: 3 * 3600) { return .seconds(300) }
        return nil
    }

    /// ¿Hay algún partido sin terminar cuyo saque caiga en la ventana dada?
    private func kickoffWithin(before: TimeInterval, after: TimeInterval) -> Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Madrid")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let now = Date()
        for day in store.matchDays {
            for game in day.games where !game.done {
                guard !game.time.isEmpty,
                      let kickoff = formatter.date(from: "\(day.date) \(game.time)") else { continue }
                let delta = kickoff.timeIntervalSince(now)
                if delta < before && delta > -after { return true }
            }
        }
        return false
    }

    // MARK: Situar la lista

    /// Coloca la lista en la sección en curso al abrir la app.
    ///
    /// Se hace dos veces a propósito: la lista es perezosa y, si el destino aún
    /// no se ha construido, la primera pasada no agarra y la app se queda
    /// enseñando la jornada 1.
    private func settleOnCurrentSection() async {
        guard let target = currentSectionID else { return }
        listAnchor = target
        try? await Task.sleep(for: .milliseconds(400))
        if Task.isCancelled { return }
        listAnchor = target
    }

    private func scroll(to id: String, proxy: ScrollViewProxy) {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation { proxy.scrollTo(id, anchor: .top) }
        }
    }

    private func scrollToCurrentIfUnfiltered(_ proxy: ScrollViewProxy) {
        guard filterTeam == nil, filterStage == nil, filterMatchday == nil,
              let target = currentSectionID else { return }
        scroll(to: target, proxy: proxy)
    }

    private func scrollToFirstSection(_ proxy: ScrollViewProxy) {
        guard let first = sections.first?.id else { return }
        scroll(to: first, proxy: proxy)
    }

    /// Sección que conviene tener a la vista: la del primer día que no ha
    /// pasado todavía.
    private var currentSectionID: String? {
        guard let focus = store.focusDate else { return sections.last?.id }
        return sections.first { section in
            section.days.contains { $0.date >= focus }
        }?.id ?? sections.last?.id
    }

    // MARK: Filtrado y agrupación

    /// Días visibles tras aplicar los filtros activos.
    private var filteredDays: [MatchDay] {
        var days = store.matchDays

        if let team = filterTeam {
            days = days.compactMap { day in
                let games = day.games.filter { $0.home == team || $0.away == team }
                guard !games.isEmpty else { return nil }
                return MatchDay(date: day.date, matchday: day.matchday, stage: day.stage, games: games)
            }
        }
        if let stage = filterStage {
            days = days.filter { $0.stage == stage }
        }
        if let matchday = filterMatchday {
            // Se muestra la jornada elegida y las siguientes: así se ve lo que
            // viene sin tener que quitar el filtro.
            days = days.filter { $0.stage != .league || ($0.matchday ?? 0) >= matchday }
        }
        return days
    }

    /// La lista, agrupada en jornadas (fase liga) y fases (cuadro).
    private var sections: [MatchSection] {
        var result: [MatchSection] = []

        let league = filteredDays.filter { $0.stage == .league }
        let byMatchday = Dictionary(grouping: league) { $0.matchday ?? 0 }
        for matchday in byMatchday.keys.sorted() {
            result.append(MatchSection(
                id: "league-\(matchday)",
                stage: .league,
                matchday: matchday,
                days: (byMatchday[matchday] ?? []).sorted { $0.date < $1.date }
            ))
        }

        for stage in Stage.allCases where stage != .league {
            let days = filteredDays.filter { $0.stage == stage }
            guard !days.isEmpty else { continue }
            result.append(MatchSection(
                id: "stage-\(stage.rawValue)",
                stage: stage,
                matchday: nil,
                days: days.sorted { $0.date < $1.date }
            ))
        }

        return result
    }

    /// Equipos del selector: primero los marcados, luego el resto por nombre.
    private var orderedTeams: [String] {
        let present = Set(store.allMatches.flatMap { [$0.home, $0.away] })
        let pool = present.isEmpty ? Set(Teams.all.map(\.key)) : present
        let sorted = pool.sorted { Teams.name($0) < Teams.name($1) }
        let marked = highlights.highlights.map(\.team).filter(pool.contains)
        return marked + sorted.filter { !marked.contains($0) }
    }

    // MARK: Estados

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(Palette.silver).scaleEffect(1.4)
            Text("state.loading")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            EuropeanCupView(size: 96).opacity(0.85)
            Text("app.title")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
            Text("state.empty.detail")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
            if let error = store.errorMessage {
                Label(error, systemImage: "wifi.slash")
                    .font(.caption)
                    .foregroundStyle(Palette.gold.opacity(0.85))
            } else {
                Text("state.pullToRefresh")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.25))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 90)
        .padding(.horizontal, 32)
    }
}

// MARK: - Barra de filtros

struct FilterBar: View {
    @Binding var filterTeam: String?
    @Binding var filterStage: Stage?
    @Binding var filterMatchday: Int?

    let teams: [String]
    let stages: [Stage]
    let matchdays: [Int]
    let highlightColor: Color?

    var body: some View {
        HStack(spacing: 8) {
            teamMenu
            stageMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.06))
        }
    }

    // MARK: Selector de equipo

    private var teamMenu: some View {
        Menu {
            Button { filterTeam = nil } label: {
                filterTeam == nil
                    ? Label("filter.allTeams", systemImage: "checkmark")
                    : Label("filter.allTeams", systemImage: "")
            }
            Divider()
            ForEach(teams, id: \.self) { team in
                Button { filterTeam = team } label: {
                    filterTeam == team
                        ? Label(Teams.name(team), systemImage: "checkmark")
                        : Label(Teams.name(team), systemImage: "")
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let team = filterTeam {
                    TeamLogoView(teamName: team, size: 16)
                    Text(Teams.name(team))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Text("filter.team")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(filterTeam == nil ? 0.5 : 1))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(teamBackground)
            .clipShape(Capsule())
        }
    }

    private var teamBackground: AnyShapeStyle {
        guard filterTeam != nil else { return AnyShapeStyle(Color.white.opacity(0.08)) }
        if let highlightColor { return AnyShapeStyle(highlightColor.opacity(0.75)) }
        return AnyShapeStyle(Palette.gold.opacity(0.8))
    }

    // MARK: Selector de fase y jornada

    private var stageMenu: some View {
        Menu {
            Button {
                filterStage = nil
                filterMatchday = nil
            } label: {
                (filterStage == nil && filterMatchday == nil)
                    ? Label("filter.allStages", systemImage: "checkmark")
                    : Label("filter.allStages", systemImage: "")
            }

            if !matchdays.isEmpty {
                Section("stage.league") {
                    ForEach(matchdays, id: \.self) { matchday in
                        Button {
                            filterStage = nil
                            filterMatchday = matchday
                        } label: {
                            filterMatchday == matchday
                                ? Label("\(matchdayLabel(matchday))", systemImage: "checkmark")
                                : Label("\(matchdayLabel(matchday))", systemImage: "")
                        }
                    }
                }
            }

            let knockout = stages.filter { $0 != .league }
            if !knockout.isEmpty {
                Section("filter.knockout") {
                    ForEach(knockout) { stage in
                        Button {
                            filterMatchday = nil
                            filterStage = stage
                        } label: {
                            filterStage == stage
                                ? Label(stage.title, systemImage: "checkmark")
                                : Label(stage.title, systemImage: "")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let stage = filterStage {
                    Text(stage.shortTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else if let matchday = filterMatchday {
                    Text(verbatim: matchdayLabel(matchday))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text("filter.stage")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(isStageFiltered ? 1 : 0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(isStageFiltered ? AnyShapeStyle(Palette.gold.opacity(0.8)) : AnyShapeStyle(Color.white.opacity(0.08)))
            .clipShape(Capsule())
        }
    }

    private var isStageFiltered: Bool { filterStage != nil || filterMatchday != nil }

    private func matchdayLabel(_ matchday: Int) -> String {
        String(format: String(localized: "matchday.short"), matchday)
    }
}

// MARK: - Sección de partidos

struct MatchSectionView: View {
    let section: MatchSection
    let onSelect: (Match) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            ForEach(section.days) { day in
                dayHeader(day)
                Divider().background(Color.white.opacity(0.04))

                ForEach(day.games) { match in
                    MatchRowView(match: match)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(match) }
                    if match.id != day.games.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.04))
                            .padding(.leading, 48)
                    }
                }

                if day.id != section.days.last?.id {
                    Divider().background(Color.white.opacity(0.07))
                }
            }

            Divider().background(Color.white.opacity(0.12))
        }
    }

    private var header: some View {
        HStack {
            Text(sectionTitle)
                .font(.caption.weight(.heavy))
                .foregroundStyle(section.stage.accent)
                .tracking(1.0)
            Spacer()
            Text(verbatim: dateRange)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.sectionHeader)
    }

    private var sectionTitle: String {
        if let matchday = section.matchday, section.stage == .league {
            return String(format: String(localized: "matchday.long"), matchday).uppercased()
        }
        return String(localized: String.LocalizationValue(stringKey(section.stage))).uppercased()
    }

    /// Traduce el `Stage` a la clave del catálogo. Hace falta porque el título
    /// se pasa por `uppercased()`, que solo trabaja con `String`.
    private func stringKey(_ stage: Stage) -> String { "stage.\(stage.rawValue)" }

    private func dayHeader(_ day: MatchDay) -> some View {
        HStack {
            Text(verbatim: Self.longDate(day.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Palette.dayHeader)
    }

    private var dateRange: String {
        guard let first = section.days.first?.date,
              let last = section.days.last?.date else { return "" }
        if first == last { return Self.shortDate(first) }
        return "\(Self.shortDate(first)) – \(Self.shortDate(last))"
    }

    // MARK: Fechas

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        return f
    }()

    /// `"8 sep"` en el idioma del usuario.
    static func shortDate(_ raw: String) -> String {
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// `"Martes 8 de septiembre"` en el idioma del usuario.
    static func longDate(_ raw: String) -> String {
        guard let date = parser.date(from: raw) else { return raw }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst
    }
}

// MARK: - Fila de partido

struct MatchRowView: View {
    let match: Match
    @Environment(HighlightSettings.self) private var highlights

    private var homeWins: Bool? {
        guard match.done, let h = match.homeScore, let a = match.awayScore else { return nil }
        return h > a
    }
    private var awayWins: Bool? {
        guard match.done, let h = match.homeScore, let a = match.awayScore else { return nil }
        return a > h
    }

    private var activeHighlight: TeamHighlight? {
        highlights.highlight(for: match.home) ?? highlights.highlight(for: match.away)
    }

    var body: some View {
        HStack(spacing: 0) {
            TeamLogoView(teamName: match.home, size: 28)
                .opacity(homeWins == false ? 0.45 : 1)
                .padding(.leading, 12)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 5) {
                teamName(match.home, wins: homeWins)
                teamName(match.away, wins: awayWins)
            }
            .padding(.vertical, 12)

            // El marcador aparece en cuanto existe, no solo al terminar:
            // durante el partido `done` es falso pero `result` ya trae el
            // tanteo en curso.
            if match.homeScore != nil {
                VStack(alignment: .trailing, spacing: 5) {
                    score(match.homeScore, winner: homeWins == true)
                    score(match.awayScore, winner: awayWins == true)
                }
                .frame(width: 18, alignment: .trailing)
                .padding(.leading, 6)
                .padding(.vertical, 12)
            }

            TeamLogoView(teamName: match.away, size: 28)
                .opacity(awayWins == false ? 0.45 : 1)
                .padding(.leading, 6)
                .padding(.trailing, 4)

            // El escudo visitante va pegado a los nombres, no en el otro
            // extremo de la fila: los dos equipos se leen juntos y la hora
            // queda sola a la derecha.
            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                statusLabel
                if let tv = match.tv, !tv.isEmpty {
                    TVBadge(channel: tv)
                }
                if let leg = match.leg {
                    Text(leg == 1 ? "leg.first" : "leg.second")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.trailing, 14)
        }
        .background(alignment: .leading) {
            if let highlight = activeHighlight {
                ZStack(alignment: .leading) {
                    highlight.color.opacity(0.12)
                    highlight.color.frame(width: 3)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if match.done {
            VStack(alignment: .trailing, spacing: 2) {
                Text("match.final")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                if let shootout = match.shootoutScore {
                    Text(verbatim: "\(shootout.0)-\(shootout.1) pen.")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.gold.opacity(0.9))
                }
            }
        } else if let live = match.liveLabel {
            HStack(spacing: 4) {
                Circle().fill(Palette.live).frame(width: 6, height: 6)
                Text(live)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.live)
                    .monospacedDigit()
            }
        } else {
            Text(verbatim: match.time.isEmpty ? "—" : match.time)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .monospacedDigit()
        }
    }

    private func teamName(_ team: String, wins: Bool?) -> some View {
        Text(verbatim: Teams.name(team))
            .font(.subheadline.weight(highlights.isHighlighted(team) ? .bold : .regular))
            .foregroundStyle(nameColor(team, wins: wins))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }

    private func nameColor(_ team: String, wins: Bool?) -> Color {
        if let highlight = highlights.highlight(for: team) {
            return highlight.color.opacity(0.95)
        }
        return wins == true ? .white : .white.opacity(0.7)
    }

    private func score(_ value: Int?, winner: Bool) -> some View {
        Text(verbatim: "\(value ?? 0)")
            .font(.subheadline.weight(winner ? .bold : .regular))
            .foregroundStyle(winner ? .white : .white.opacity(0.45))
            .monospacedDigit()
    }
}

// MARK: - Distintivo de televisión

struct TVBadge: View {
    let channel: String

    private var background: Color {
        switch channel.uppercased() {
        case "MOVISTAR", "M+", "MOVISTAR+": return Color(hex: 0x0077B6)
        case "DAZN":                        return Color(hex: 0xF5A623)
        case "TVE", "LA 1":                 return Color(hex: 0xE63946)
        default:                            return Color(hex: 0x3A4256)
        }
    }

    var body: some View {
        Text(verbatim: channel)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Utilidades

extension String {
    /// Pone en mayúscula solo la primera letra, respetando el resto.
    ///
    /// `capitalized` pondría en mayúscula cada palabra, y en castellano y en
    /// catalán los meses van en minúscula: «Martes 8 de Septiembre» está mal.
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

#Preview {
    ContentView()
}
