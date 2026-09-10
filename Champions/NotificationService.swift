//
//  NotificationService.swift
//  Champions
//
//  Los avisos van por dos caminos distintos, y conviene no confundirlos:
//
//  · **En vivo** (gol, penalti, roja, principio y final) llegan por APNs desde
//    el NAS, que es quien mira los partidos cada minuto. La app solo se da de
//    alta indicando qué equipos sigue.
//
//  · **Recordatorio antes del saque** es local: lo programa el propio teléfono
//    a partir del calendario, sin que intervenga nadie. Así funciona incluso
//    con el NAS apagado.
//

import Foundation
import UserNotifications

// MARK: - NotificationService

@Observable
final class NotificationService: @unchecked Sendable {

    static let shared = NotificationService()

    /// Base del servicio del NAS. Es el mismo contenedor que atiende a la app
    /// de La Liga, con rutas propias para esta competición.
    private static let backendBase = "https://laliga-api.cornellanas.net"

    /// APNs tiene dos entornos y el token de uno no vale en el otro.
    private static let apnsEnvironment: String = {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }()

    /// iOS solo mantiene **64 notificaciones locales pendientes** por app. Con
    /// 189 partidos en el torneo no caben ni de lejos, así que se programa solo
    /// una ventana por delante y se rehace cada vez que la app pasa a primer
    /// plano. Se deja margen por debajo del tope del sistema.
    private static let maxPendingReminders = 48

    private(set) var deviceToken: String?

    /// Cómo fue el último intento de darse de alta en el NAS.
    ///
    /// Existe porque no tenerlo salió caro: entre el 2 y el 10 de septiembre
    /// de 2026 el NAS devolvió 404 en cada arranque —la ruta de la Champions
    /// estaba escrita pero sin desplegar— y la app no se enteró ni una sola
    /// vez, porque tiraba la respuesta sin mirarla. Ocho días sin un aviso en
    /// vivo y sin nada en pantalla que lo indicara. El recordatorio del saque
    /// seguía llegando, que lo programa el propio teléfono, así que ni
    /// siquiera parecía que hubiera nada roto.
    private(set) var registration: RegistrationState = .idle

    enum RegistrationState: Equatable {
        /// No procede: los avisos están apagados o no hay ningún equipo marcado.
        case idle
        /// Se está intentando ahora mismo.
        case trying
        /// El NAS lo aceptó. La fecha es la del último alta confirmada.
        case active(Date)
        case failed(Failure)

        enum Failure: Equatable {
            /// No hubo respuesta: sin red, o el NAS apagado.
            case unreachable
            /// El NAS contestó, pero no conoce esa ruta. Reintentar no arregla
            /// nada: o no está desplegado, o la app apunta a donde no debe.
            case routeMissing
            /// Cualquier otro código de error.
            case server(Int)
        }
    }

    private var lastTeams: [String] = []
    private var lastPrefs = NotificationPrefs()

    private init() {
        deviceToken = UserDefaults.standard.string(forKey: "champions_apns_token")
    }

    // MARK: Registro en el servidor

    /// Guarda el estado actual sin tocar la red. Lo llama `HighlightSettings`
    /// al arrancar, para poder registrarse en cuanto llegue el token.
    func updateCache(teams: [String], prefs: NotificationPrefs) {
        lastTeams = teams
        lastPrefs = prefs
    }

    /// Recibe el token que entrega APNs y se da de alta si procede.
    func setToken(_ tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: "champions_apns_token")
        deviceToken = hex
        sync(teams: lastTeams, prefs: lastPrefs)
    }

    /// Da de alta o de baja el dispositivo según las preferencias actuales.
    func sync(teams: [String], prefs: NotificationPrefs) {
        lastTeams = teams
        lastPrefs = prefs
        guard let token = deviceToken, !token.isEmpty else { return }

        guard prefs.enabled && !teams.isEmpty else {
            // La baja no se vigila: que falle no le quita nada al usuario, y
            // el NAS deja de mandar en cuanto APNs le diga que el token ya no
            // vale.
            Task { _ = await self.enviar("/champions/unregister",
                                         cuerpo: ["deviceToken": token]) }
            setRegistration(.idle)
            return
        }

        darseDeAlta(token: token, teams: teams, prefs: prefs)
    }

    /// Vuelve a intentar el alta con lo último que se sabe. Lo llama el botón
    /// de reintentar de los ajustes.
    func retry() {
        sync(teams: lastTeams, prefs: lastPrefs)
    }

    private func darseDeAlta(token: String, teams: [String], prefs: NotificationPrefs) {
        let cuerpo: [String: Any] = [
            "deviceToken": token,
            "environment": Self.apnsEnvironment,
            "competition": "uefa.champions",
            "teams": teams,
            "prefs": [
                "enabled": prefs.enabled,
                "goals": prefs.goals,
                "penalties": prefs.penalties,
                "redCards": prefs.redCards,
                "startEnd": prefs.startEnd,
            ],
        ]

        setRegistration(.trying)

        Task {
            // Un tropiezo de red al vuelo es normal —el móvil salta de la wifi
            // a los datos, el túnel del NAS tarda en levantar—, así que se
            // reintenta un par de veces antes de dar la voz de alarma. Lo que
            // no se puede es callarlo indefinidamente.
            var ultimo: RegistrationState.Failure = .unreachable
            for espera in [0, 3, 12] {
                if espera > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(espera) * 1_000_000_000)
                }
                guard let fallo = await self.enviar("/champions/register", cuerpo: cuerpo) else {
                    self.setRegistration(.active(Date()))
                    return
                }
                ultimo = fallo
                // Un 404 no se cura esperando: el servidor no tiene la ruta.
                if fallo == .routeMissing { break }
            }
            self.setRegistration(.failed(ultimo))
        }
    }

    private func setRegistration(_ estado: RegistrationState) {
        Task { @MainActor in self.registration = estado }
    }

    /// Manda una petición al NAS. Devuelve `nil` si la aceptó, o el motivo.
    private func enviar(_ path: String, cuerpo: [String: Any]) async -> RegistrationState.Failure? {
        guard let url = URL(string: Self.backendBase + path),
              let data = try? JSONSerialization.data(withJSONObject: cuerpo) else {
            return .server(0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 10

        do {
            let (_, respuesta) = try await URLSession.shared.data(for: request)
            guard let http = respuesta as? HTTPURLResponse else { return .unreachable }
            switch http.statusCode {
            case 200..<300: return nil
            case 404:       return .routeMissing
            default:        return .server(http.statusCode)
            }
        } catch {
            return .unreachable
        }
    }

    // MARK: Permiso

    /// Pide permiso al usuario para avisar. Devuelve si lo concedió.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        if granted {
            await MainActor.run { UIApplicationShim.registerForRemoteNotifications() }
        }
        return granted
    }

    /// Estado actual del permiso del sistema.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: Recordatorios locales

    /// Reprograma los recordatorios de saque de los equipos marcados.
    ///
    /// Se borran los pendientes y se vuelven a crear a partir del calendario
    /// que hay ahora en pantalla: es la única forma de que el recordatorio
    /// siga al partido cuando UEFA cambia una hora.
    ///
    /// - Parameters:
    ///   - matchDays: Calendario completo tal como lo tiene el store.
    ///   - teams: Equipos marcados por el usuario.
    ///   - prefs: Preferencias de aviso.
    func rescheduleKickoffReminders(matchDays: [MatchDay],
                                    teams: [String],
                                    prefs: NotificationPrefs) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        guard prefs.enabled, prefs.kickoffReminder, !teams.isEmpty else { return }
        guard await authorizationStatus() == .authorized else { return }

        let seguidos = Set(teams)
        let antelacion = TimeInterval(prefs.kickoffReminderMinutes * 60)
        let ahora = Date()
        var programados = 0

        for day in matchDays {
            for match in day.games where !match.done {
                guard seguidos.contains(match.home) || seguidos.contains(match.away) else { continue }
                guard let kickoff = Self.kickoffDate(date: day.date, time: match.time) else { continue }

                let fireDate = kickoff.addingTimeInterval(-antelacion)
                guard fireDate > ahora else { continue }

                let content = UNMutableNotificationContent()
                content.title = String(localized: "reminder.title")
                content.body = String(
                    format: String(localized: "reminder.body"),
                    Teams.name(match.home),
                    Teams.name(match.away),
                    prefs.kickoffReminderMinutes
                )
                content.sound = .default
                content.userInfo = ["matchID": match.id]

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: fireDate
                )
                let request = UNNotificationRequest(
                    identifier: "kickoff-\(match.id)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                try? await center.add(request)

                programados += 1
                if programados >= Self.maxPendingReminders { return }
            }
        }
    }

    /// Convierte fecha y hora del calendario (siempre hora de Madrid) a `Date`.
    private static func kickoffDate(date: String, time: String) -> Date? {
        guard !time.isEmpty, time != "--:--" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Madrid")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: "\(date) \(time)")
    }
}

// MARK: - Puente con UIKit

#if canImport(UIKit)
import UIKit

/// Envoltorio mínimo sobre `UIApplication` para no importar UIKit por toda la
/// app solo por una llamada.
enum UIApplicationShim {
    @MainActor
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}
#else
enum UIApplicationShim {
    @MainActor static func registerForRemoteNotifications() {}
}
#endif
