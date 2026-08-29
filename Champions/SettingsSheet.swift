//
//  SettingsSheet.swift
//  Champions
//
//  Ajustes: qué equipos seguir y qué avisos recibir de ellos.
//

import SwiftUI
import UserNotifications

struct SettingsSheet: View {

    @Bindable var settings: HighlightSettings
    let store: MatchStore

    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var followed: [TeamHighlight] { settings.highlights }

    private var candidates: [Team] {
        let pool = Teams.sortedForDisplay.filter { !settings.isHighlighted($0.key) }
        guard !search.isEmpty else { return pool }
        return pool.filter { $0.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                followedSection
                notificationsSection
                addSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("action.done") { dismiss() }
                }
            }
            .task { authorization = await NotificationService.shared.authorizationStatus() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Equipos seguidos

    private var followedSection: some View {
        Section {
            if followed.isEmpty {
                Text("settings.noTeams")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(followed) { highlight in
                    HStack(spacing: 10) {
                        TeamLogoView(teamName: highlight.team, size: 26)
                        Text(verbatim: Teams.name(highlight.team))
                            .foregroundStyle(.white)
                        Spacer()
                        colorPicker(for: highlight)
                    }
                }
                .onDelete { settings.remove(at: $0) }
            }
        } header: {
            Text("settings.followed")
        } footer: {
            Text("settings.followed.help")
        }
    }

    private func colorPicker(for highlight: TeamHighlight) -> some View {
        Menu {
            ForEach(HighlightSettings.palette, id: \.self) { hex in
                Button {
                    settings.setColor(hex, for: highlight.team)
                } label: {
                    Label {
                        Text(verbatim: String(format: "#%06X", hex))
                    } icon: {
                        Image(systemName: hex == highlight.colorHex ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
        } label: {
            Circle()
                .fill(highlight.color)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
        }
        .accessibilityLabel("a11y.teamColor")
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
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text(String(format: String(localized: "settings.minutes"), minutes)).tag(minutes)
                        }
                    }
                    .onChange(of: settings.notifications.kickoffReminderMinutes) { _, _ in
                        Task { await reschedule() }
                    }
                }
            }

            if settings.notifications.enabled && authorization == .denied {
                Label("settings.notifications.denied", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Palette.gold)
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

    // MARK: Añadir equipo

    private var addSection: some View {
        Section {
            ForEach(candidates) { team in
                Button {
                    settings.add(team: team.key)
                    search = ""
                } label: {
                    HStack(spacing: 10) {
                        TeamLogoView(teamName: team.key, size: 24)
                        Text(verbatim: team.displayName)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Palette.gold)
                    }
                }
            }
        } header: {
            Text("settings.addTeam")
        }
        .searchable(text: $search, prompt: Text("settings.searchTeam"))
    }

    // MARK: Acerca de

    private var aboutSection: some View {
        Section {
            LabeledContent("settings.season") {
                Text(verbatim: store.selectedSeason.displayName)
            }
            LabeledContent("settings.lastUpdate") {
                if let updated = store.lastUpdated {
                    Text(updated.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text(verbatim: "—")
                }
            }
            if let source = store.source.label {
                LabeledContent("settings.source") { Text(source) }
            }
        } header: {
            Text("settings.about")
        } footer: {
            Text("settings.data.credit")
        }
    }
}
