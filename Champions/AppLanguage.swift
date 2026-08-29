//
//  AppLanguage.swift
//  Champions
//
//  Elegir el idioma dentro de la app, sin pasar por los Ajustes de iOS.
//
//  Por defecto la app va en el idioma del teléfono, que es lo que espera casi
//  todo el mundo. Pero aquí hace falta poder cambiarlo a mano: un iPhone en
//  castellano no tiene por qué querer la app en castellano, y comprobar que las
//  tres traducciones están bien es imposible si hay que cambiar el idioma del
//  sistema entero para verlas.
//
//  Se hace escribiendo `AppleLanguages` en las preferencias, que es el
//  mecanismo del propio sistema. Tiene una pega conocida y sin remedio: el
//  paquete de idiomas se resuelve al arrancar, así que **el cambio se ve al
//  volver a abrir la app**. La pantalla lo dice en vez de dejar al usuario
//  pensando que no ha funcionado.
//

import Foundation
import SwiftUI

/// Idioma en el que corre la app.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    /// El del teléfono. Es el valor por defecto.
    case system
    case catalan = "ca"
    case spanish = "es"
    case english = "en"

    var id: String { rawValue }

    /// Nombre del idioma escrito en ese mismo idioma, que es como se reconoce
    /// de un vistazo aunque no entiendas el idioma en el que está la app.
    var title: LocalizedStringKey {
        switch self {
        case .system:  return "language.system"
        case .catalan: return "language.catalan"
        case .spanish: return "language.spanish"
        case .english: return "language.english"
        }
    }

    /// Códigos que se escriben en `AppleLanguages`, o `nil` para dejar mandar
    /// al sistema.
    var appleLanguages: [String]? {
        switch self {
        case .system:  return nil
        case .catalan: return ["ca", "es", "en"]
        case .spanish: return ["es", "ca", "en"]
        case .english: return ["en", "es", "ca"]
        }
    }
}

// MARK: - Preferencia

@Observable
@MainActor
final class LanguagePreference {

    private static let key = "champions_language_v1"
    private static let appleKey = "AppleLanguages"

    /// Idioma elegido. Al cambiarlo se anota en las preferencias del sistema.
    var selected: AppLanguage {
        didSet {
            guard selected != oldValue else { return }
            persist()
        }
    }

    /// `true` cuando se ha cambiado el idioma y todavía no se ha reabierto la
    /// app, que es cuando surte efecto.
    private(set) var needsRestart = false

    init() {
        let guardado = UserDefaults.standard.string(forKey: Self.key)
        selected = guardado.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Idioma en el que se está dibujando la app ahora mismo.
    ///
    /// No tiene por qué coincidir con `selected`: si se acaba de cambiar y no
    /// se ha reabierto, sigue mandando el anterior.
    var activeCode: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(selected.rawValue, forKey: Self.key)

        if let idiomas = selected.appleLanguages {
            defaults.set(idiomas, forKey: Self.appleKey)
        } else {
            // Quitar la clave devuelve el mando al idioma del teléfono.
            defaults.removeObject(forKey: Self.appleKey)
        }
        needsRestart = true
    }
}
