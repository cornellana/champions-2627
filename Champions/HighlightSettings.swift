//
//  HighlightSettings.swift
//  Champions
//
//  Equipos que el usuario quiere seguir de cerca: se resaltan en la lista y son
//  los que generan avisos. Se guarda en `UserDefaults`, que para un puñado de
//  preferencias es el sitio adecuado.
//

import Foundation
import SwiftUI

// MARK: - TeamHighlight

/// Un equipo marcado por el usuario, con el color con el que quiere verlo.
struct TeamHighlight: Codable, Identifiable, Equatable, Sendable {
    var id: String { team }
    /// Nombre canónico del equipo (la clave del catálogo `Teams`).
    var team: String
    var colorHex: UInt

    var color: Color { Color(hex: colorHex) }
}

// MARK: - NotificationPrefs

/// Qué avisos quiere recibir el usuario de sus equipos.
struct NotificationPrefs: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var goals: Bool = true
    var penalties: Bool = true
    var redCards: Bool = true
    var startEnd: Bool = true
    /// Recordatorio en el móvil un rato antes del saque. Es local, no depende
    /// del servidor de avisos.
    var kickoffReminder: Bool = true
    /// Minutos de antelación del recordatorio.
    var kickoffReminderMinutes: Int = 15
}

// MARK: - HighlightSettings

@Observable
@MainActor
final class HighlightSettings {

    private static let highlightKey = "champions_highlights_v1"
    private static let notifKey = "champions_notifications_v1"

    /// Paleta que se ofrece al marcar un equipo.
    static let palette: [UInt] = [
        0xD4A03C, 0x2C5FE0, 0x1B8A4C, 0xC0392B,
        0x8B3FB0, 0xE07B2C, 0x18A5A5, 0xD1477A,
    ]

    var highlights: [TeamHighlight] {
        didSet {
            persistHighlights()
            syncRemote()
        }
    }

    var notifications: NotificationPrefs {
        didSet {
            persistNotifications()
            syncRemote()
        }
    }

    init() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: Self.highlightKey),
           let decoded = try? JSONDecoder().decode([TeamHighlight].self, from: data) {
            highlights = decoded
        } else {
            highlights = []
        }

        if let data = defaults.data(forKey: Self.notifKey),
           let decoded = try? JSONDecoder().decode(NotificationPrefs.self, from: data) {
            notifications = decoded
        } else {
            notifications = NotificationPrefs()
        }

        // Se cachea para que el servicio pueda registrarse en cuanto APNs
        // entregue el token, sin esperar a que el usuario toque nada.
        NotificationService.shared.updateCache(
            teams: highlights.map(\.team),
            prefs: notifications
        )
    }

    // MARK: Consultas

    func highlight(for team: String) -> TeamHighlight? {
        highlights.first { $0.team == team }
    }

    func isHighlighted(_ team: String) -> Bool {
        highlights.contains { $0.team == team }
    }

    /// `true` si alguno de los dos equipos del partido está marcado.
    func involvesHighlighted(_ match: Match) -> Bool {
        isHighlighted(match.home) || isHighlighted(match.away)
    }

    // MARK: Mutaciones

    /// Marca un equipo. Si ya lo estaba no hace nada.
    func add(team: String) {
        guard !isHighlighted(team) else { return }
        let used = Set(highlights.map(\.colorHex))
        let color = Self.palette.first { !used.contains($0) } ?? Self.palette[highlights.count % Self.palette.count]
        highlights.append(TeamHighlight(team: team, colorHex: color))
    }

    func remove(team: String) {
        highlights.removeAll { $0.team == team }
    }

    func remove(at offsets: IndexSet) {
        highlights.remove(atOffsets: offsets)
    }

    func toggle(team: String) {
        isHighlighted(team) ? remove(team: team) : add(team: team)
    }

    func setColor(_ hex: UInt, for team: String) {
        guard let index = highlights.firstIndex(where: { $0.team == team }) else { return }
        highlights[index].colorHex = hex
    }

    // MARK: Persistencia

    private func persistHighlights() {
        guard let data = try? JSONEncoder().encode(highlights) else { return }
        UserDefaults.standard.set(data, forKey: Self.highlightKey)
    }

    private func persistNotifications() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        UserDefaults.standard.set(data, forKey: Self.notifKey)
    }

    private func syncRemote() {
        NotificationService.shared.sync(teams: highlights.map(\.team), prefs: notifications)
    }
}
