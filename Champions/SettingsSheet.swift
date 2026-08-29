//
//  SettingsSheet.swift
//  Champions
//
//  Ajustes: qué equipos seguir y de qué color, qué avisos recibir y en qué
//  idioma va la app.
//
//  Los equipos se añaden desde una hoja aparte, con selector y paleta, igual
//  que en la app de La Liga. La primera versión de esta pantalla los ponía como
//  una lista de botones dentro del `List`, y tocar uno marcaba varios de golpe:
//  la lista se rehacía en mitad del gesto —el equipo elegido desaparece de los
//  candidatos— y el toque acababa cayendo en la fila que ocupaba su sitio.
//

import SwiftUI
import UserNotifications

struct SettingsSheet: View {

    @Bindable var settings: HighlightSettings
    let store: MatchStore

    /// Llega desde la raíz: si la hoja se creara la suya, el cambio se
    /// perdería al cerrarla.
    @Bindable var language: LanguagePreference

    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var showingAddTeam = false
    @Environment(\.dismiss) private var dismiss

    /// Equipos que todavía no se siguen.
    private var available: [Team] {
        Teams.sortedForDisplay.filter { !settings.isHighlighted($0.key) }
    }

    var body: some View {
        NavigationStack {
            List {
                followedSection
                addSection
                notificationsSection
                languageSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
                        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .principal) {
                    Text("settings.title")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddTeam) {
                AddTeamSheet(teams: available, suggested: settings.suggestedColor) { team, color in
                    settings.add(team: team, color: color)
                }
            }
            .task { authorization = await NotificationService.shared.authorizationStatus() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Equipos seguidos

    private var followedSection: some View {
        Section {
            if settings.highlights.isEmpty {
                Text("settings.noTeams")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach($settings.highlights) { $highlight in
                    FollowedTeamRow(highlight: $highlight)
                }
                .onDelete { settings.remove(at: $0) }
            }
        } header: {
            Text("settings.followed")
        } footer: {
            Text("settings.followed.help")
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showingAddTeam = true
            } label: {
                Label("settings.addTeam", systemImage: "plus.circle.fill")
            }
            .disabled(available.isEmpty)
        }
    }

    // MARK: Avisos

    private var notificationsSection: some View {
        Section {
            Toggle("settings.notifications.enabled", isOn: $settings.notifications.enabled)
                .onChange(of: settings.notifications.enabled) { _, enabled in
                    guard enabled else { return }
                    Task {
                        await NotificationService.shared.requestAuthorization()
                        authorization = await NotificationService.shared.authorizationStatus()
                        await reschedule()
                    }
                }

            if settings.notifications.enabled {
                Toggle("settings.notifications.goals", isOn: $settings.notifications.goals)
                Toggle("settings.notifications.penalties", isOn: $settings.notifications.penalties)
                Toggle("settings.notifications.redCards", isOn: $settings.notifications.redCards)
                Toggle("settings.notifications.startEnd", isOn: $settings.notifications.startEnd)

                Toggle("settings.notifications.kickoff", isOn: $settings.notifications.kickoffReminder)
                    .onChange(of: settings.notifications.kickoffReminder) { _, _ in
                        Task { await reschedule() }
                    }

                if settings.notifications.kickoffReminder {
                    Picker("settings.notifications.kickoffMinutes",
                           selection: $settings.notifications.kickoffReminderMinutes) {
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutos in
                            Text(String(format: String(localized: "settings.minutes"), minutos))
                                .tag(minutos)
                        }
                    }
                    .onChange(of: settings.notifications.kickoffReminderMinutes) { _, _ in
                        Task { await reschedule() }
                    }
                }
            }

            if settings.notifications.enabled && authorization == .denied {
                Label("settings.notifications.denied", systemImage: "bell.slash.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.gold)
                Button("settings.notifications.openSettings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.subheadline)
            }
        } header: {
            Text("settings.notifications")
        } footer: {
            Text("settings.notifications.help")
        }
    }

    private func reschedule() async {
        await NotificationService.shared.rescheduleKickoffReminders(
            matchDays: store.matchDays,
            teams: settings.highlights.map(\.team),
            prefs: settings.notifications
        )
    }

    // MARK: Idioma

    private var languageSection: some View {
        Section {
            Picker("settings.language", selection: $language.selected) {
                ForEach(AppLanguage.allCases) { idioma in
                    Text(idioma.title).tag(idioma)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()

            if language.needsRestart {
                Label("settings.language.restart", systemImage: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(Palette.gold)
            }
        } header: {
            Text("settings.language")
        } footer: {
            Text("settings.language.help")
        }
    }

    // MARK: Acerca de

    private var aboutSection: some View {
        Section {
            LabeledContent("settings.season") {
                Text(verbatim: store.selectedSeason.displayName)
            }
            LabeledContent("settings.lastUpdate") {
                if let actualizado = store.lastUpdated {
                    Text(actualizado.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text(verbatim: "—")
                }
            }
            if let origen = store.source.label {
                LabeledContent("settings.source") { Text(origen) }
            }
        } header: {
            Text("settings.about")
        } footer: {
            Text("settings.data.credit")
        }
    }
}

// MARK: - Fila de equipo seguido

/// Un equipo de la lista, con su color cambiable en el sitio.
private struct FollowedTeamRow: View {

    @Binding var highlight: TeamHighlight

    /// El `ColorPicker` necesita un `Color`, no un entero, y se sincroniza en
    /// las dos direcciones: se rellena al aparecer y escribe al cambiar.
    @State private var color: Color = .blue

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3)
                .fill(highlight.color)
                .frame(width: 4, height: 36)

            TeamLogoView(teamName: highlight.team, size: 32)

            Text(verbatim: Teams.name(highlight.team))
                .font(.subheadline)
                .foregroundStyle(.white)

            Spacer()

            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 34, height: 34)
                .onChange(of: color) { _, nuevo in
                    highlight.colorHex = nuevo.toHex()
                }
                .accessibilityLabel("a11y.teamColor")
        }
        .padding(.vertical, 4)
        .onAppear { color = highlight.color }
    }
}

// MARK: - Hoja de añadir equipo

/// Elegir equipo y color en una hoja aparte, con vista previa de cómo quedará
/// la fila en la lista de partidos.
struct AddTeamSheet: View {

    let teams: [Team]
    let suggested: Color
    let onAdd: (String, Color) -> Void

    @State private var team: String = ""
    @State private var color: Color = .blue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("settings.team") {
                    Picker("settings.team", selection: $team) {
                        ForEach(teams) { equipo in
                            HStack {
                                TeamLogoView(teamName: equipo.key, size: 24)
                                Text(verbatim: equipo.displayName)
                            }
                            .tag(equipo.key)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section("settings.highlightColor") {
                    ColorPicker("settings.highlightColor", selection: $color, supportsOpacity: false)

                    // Paleta rápida: el ColorPicker del sistema es completo pero
                    // lento para lo habitual, que es coger un color distinto de
                    // los que ya hay.
                    HStack(spacing: 10) {
                        ForEach(HighlightSettings.palette, id: \.self) { hex in
                            Button {
                                color = Color(hex: hex)
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle().stroke(.white.opacity(
                                            color.toHex() == hex ? 0.9 : 0.15), lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    preview
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("settings.addTeam")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.add") {
                        guard !team.isEmpty else { return }
                        onAdd(team, color)
                        dismiss()
                    }
                    .disabled(team.isEmpty)
                    .bold()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            team = teams.first?.key ?? ""
            color = suggested
        }
    }

    /// Cómo se verá la fila del partido en la lista.
    private var preview: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 4, height: 40)
            if !team.isEmpty {
                TeamLogoView(teamName: team, size: 28)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: team.isEmpty ? "—" : Teams.name(team))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                Text("settings.preview.rival")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
