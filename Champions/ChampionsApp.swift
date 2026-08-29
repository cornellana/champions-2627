//
//  ChampionsApp.swift
//  Champions
//
//  Punto de entrada. El delegado existe solo para recoger el token de APNs:
//  SwiftUI todavía no ofrece esa pieza por sí solo.
//

import SwiftUI
import UserNotifications

@main
struct ChampionsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Solo se pide el registro si el usuario ya dio permiso antes: abrir la
        // app por primera vez no debe soltarle un diálogo del sistema sin que
        // haya pedido nada.
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status == .authorized {
                await MainActor.run { application.registerForRemoteNotifications() }
            }
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.setToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Sin token no hay avisos en vivo, pero la app sigue siendo útil: el
        // calendario, los resultados y los recordatorios locales no dependen
        // de APNs.
        print("[APNs] registro fallido: \(error.localizedDescription)")
    }

    /// Enseña el aviso aunque la app esté abierta: si el usuario está mirando
    /// otra pantalla, el gol de su equipo debe verse igual.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
    -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
