//
//  Teams.swift
//  Champions
//
//  Catálogo de los 36 clubes de la fase liga 2026-27.
//
//  El nombre canónico (`key`) es el que viaja en el JSON y con el que se cruzan
//  resultados, clasificación y goleadores. Todo lo demás —el nombre que ve el
//  usuario en cada idioma, el escudo, el color— se resuelve aquí, para que el
//  dato y su presentación no se estorben.
//

import SwiftUI

// MARK: - Team

/// Un club del torneo.
struct Team: Identifiable, Hashable, Sendable {

    /// Nombre canónico, tal como aparece en el JSON.
    let key: String
    /// Identificador del club en ESPN. Sirve para el escudo y para la plantilla.
    let espnID: Int
    /// Abreviatura de tres o cuatro letras, para las vistas estrechas.
    let abbr: String
    /// Color principal del club, `0xRRGGBB`.
    let colorHex: UInt
    /// Código ISO del país, para la bandera.
    let country: String
    /// Liga doméstica en ESPN (`"esp.1"`), de donde se saca la plantilla.
    ///
    /// Es `nil` en los cuatro clubes cuya liga ESPN no cubre —Shajtar, Slavia,
    /// Slovan y Sabah—. Para ellos la plantilla se reconstruye a partir de los
    /// jugadores que van apareciendo en las alineaciones de sus partidos.
    let domesticLeague: String?
    /// Nombre en catalán.
    let ca: String
    /// Nombre en castellano.
    let es: String
    /// Nombre en inglés.
    let en: String

    var id: String { key }

    /// Color del club como `Color`.
    var color: Color { Color(hex: colorHex) }

    /// URL del escudo en el CDN de ESPN, a 500 px.
    var badgeURL: URL? {
        URL(string: "https://a.espncdn.com/i/teamlogos/soccer/500/\(espnID).png")
    }

    /// Nombre del club en el idioma en el que corre la app.
    ///
    /// Los nombres de club no son cadenas traducibles al uso —no van al catálogo
    /// de idiomas— porque son datos: llegan del JSON y hay que resolverlos en
    /// tiempo de ejecución, no en tiempo de compilación.
    var displayName: String {
        switch Locale.current.language.languageCode?.identifier {
        case "ca": return ca
        case "en": return en
        default:   return es
        }
    }
}

// MARK: - Catálogo

enum Teams {

    /// Los 36 clubes de la fase liga, en orden alfabético por nombre canónico.
    static let all: [Team] = [
        Team(key: "AEK Atenas", espnID: 887, abbr: "AEK", colorHex: 0xFFDD00, country: "GR", domesticLeague: "gre.1",
             ca: "AEK Atenes", es: "AEK Atenas", en: "AEK Athens"),
        Team(key: "Arsenal", espnID: 359, abbr: "ARS", colorHex: 0xE20520, country: "GB", domesticLeague: "eng.1",
             ca: "Arsenal", es: "Arsenal", en: "Arsenal"),
        Team(key: "Aston Villa", espnID: 362, abbr: "AVL", colorHex: 0x660E36, country: "GB", domesticLeague: "eng.1",
             ca: "Aston Villa", es: "Aston Villa", en: "Aston Villa"),
        Team(key: "Atlético de Madrid", espnID: 1068, abbr: "ATM", colorHex: 0xCA3624, country: "ES", domesticLeague: "esp.1",
             ca: "Atlètic de Madrid", es: "Atlético de Madrid", en: "Atlético Madrid"),
        Team(key: "Bayern de Múnich", espnID: 132, abbr: "BAY", colorHex: 0xDC052D, country: "DE", domesticLeague: "ger.1",
             ca: "Bayern de Munic", es: "Bayern de Múnich", en: "Bayern Munich"),
        Team(key: "Bodø/Glimt", espnID: 2980, abbr: "BOD", colorHex: 0xD9C400, country: "NO", domesticLeague: "nor.1",
             ca: "Bodø/Glimt", es: "Bodø/Glimt", en: "Bodø/Glimt"),
        Team(key: "Borussia Dortmund", espnID: 124, abbr: "DOR", colorHex: 0xD9C400, country: "DE", domesticLeague: "ger.1",
             ca: "Borussia Dortmund", es: "Borussia Dortmund", en: "Borussia Dortmund"),
        Team(key: "Brujas", espnID: 570, abbr: "BRU", colorHex: 0x0081FF, country: "BE", domesticLeague: "bel.1",
             ca: "Bruges", es: "Brujas", en: "Club Brugge"),
        Team(key: "Como", espnID: 2572, abbr: "COM", colorHex: 0x4169E1, country: "IT", domesticLeague: "ita.1",
             ca: "Como", es: "Como", en: "Como"),
        Team(key: "FC Barcelona", espnID: 83, abbr: "BAR", colorHex: 0x990000, country: "ES", domesticLeague: "esp.1",
             ca: "FC Barcelona", es: "FC Barcelona", en: "FC Barcelona"),
        Team(key: "Fenerbahçe", espnID: 436, abbr: "FEN", colorHex: 0xD9C400, country: "TR", domesticLeague: "tur.1",
             ca: "Fenerbahçe", es: "Fenerbahçe", en: "Fenerbahçe"),
        Team(key: "Feyenoord", espnID: 142, abbr: "FEY", colorHex: 0xEF2F24, country: "NL", domesticLeague: "ned.1",
             ca: "Feyenoord", es: "Feyenoord", en: "Feyenoord"),
        Team(key: "Galatasaray", espnID: 432, abbr: "GAL", colorHex: 0xAA0031, country: "TR", domesticLeague: "tur.1",
             ca: "Galatasaray", es: "Galatasaray", en: "Galatasaray"),
        Team(key: "Inter de Milán", espnID: 110, abbr: "INT", colorHex: 0x00239C, country: "IT", domesticLeague: "ita.1",
             ca: "Inter de Milà", es: "Inter de Milán", en: "Inter Milan"),
        Team(key: "LASK", espnID: 4411, abbr: "LAS", colorHex: 0x2B2B2B, country: "AT", domesticLeague: "aut.1",
             ca: "LASK", es: "LASK", en: "LASK"),
        Team(key: "Lens", espnID: 175, abbr: "LEN", colorHex: 0xE91514, country: "FR", domesticLeague: "fra.1",
             ca: "Lens", es: "Lens", en: "Lens"),
        Team(key: "Lille", espnID: 166, abbr: "LIL", colorHex: 0xC2051B, country: "FR", domesticLeague: "fra.1",
             ca: "Lilla", es: "Lille", en: "Lille"),
        Team(key: "Liverpool", espnID: 364, abbr: "LIV", colorHex: 0xD11317, country: "GB", domesticLeague: "eng.1",
             ca: "Liverpool", es: "Liverpool", en: "Liverpool"),
        Team(key: "Manchester City", espnID: 382, abbr: "MCI", colorHex: 0x6CABDD, country: "GB", domesticLeague: "eng.1",
             ca: "Manchester City", es: "Manchester City", en: "Manchester City"),
        Team(key: "Manchester United", espnID: 360, abbr: "MUN", colorHex: 0xDA020E, country: "GB", domesticLeague: "eng.1",
             ca: "Manchester United", es: "Manchester United", en: "Manchester United"),
        Team(key: "Nápoles", espnID: 114, abbr: "NAP", colorHex: 0x0677D2, country: "IT", domesticLeague: "ita.1",
             ca: "Nàpols", es: "Nápoles", en: "Napoli"),
        Team(key: "Oporto", espnID: 437, abbr: "POR", colorHex: 0x0000DD, country: "PT", domesticLeague: "por.1",
             ca: "Porto", es: "Oporto", en: "Porto"),
        Team(key: "PSV", espnID: 148, abbr: "PSV", colorHex: 0xEF2F24, country: "NL", domesticLeague: "ned.1",
             ca: "PSV", es: "PSV", en: "PSV"),
        Team(key: "Paris Saint-Germain", espnID: 160, abbr: "PSG", colorHex: 0x011F68, country: "FR", domesticLeague: "fra.1",
             ca: "Paris Saint-Germain", es: "Paris Saint-Germain", en: "Paris Saint-Germain"),
        Team(key: "RB Leipzig", espnID: 11420, abbr: "RBL", colorHex: 0xD3062E, country: "DE", domesticLeague: "ger.1",
             ca: "RB Leipzig", es: "RB Leipzig", en: "RB Leipzig"),
        Team(key: "Real Betis", espnID: 244, abbr: "BET", colorHex: 0x288A00, country: "ES", domesticLeague: "esp.1",
             ca: "Reial Betis", es: "Real Betis", en: "Real Betis"),
        Team(key: "Real Madrid", espnID: 86, abbr: "RMA", colorHex: 0x1B4D3E, country: "ES", domesticLeague: "esp.1",
             ca: "Reial Madrid", es: "Real Madrid", en: "Real Madrid"),
        Team(key: "Roma", espnID: 104, abbr: "ROM", colorHex: 0x990A2C, country: "IT", domesticLeague: "ita.1",
             ca: "Roma", es: "Roma", en: "Roma"),
        Team(key: "Sabah", espnID: 21922, abbr: "SAB", colorHex: 0x1A1A1A, country: "AZ", domesticLeague: nil,
             ca: "Sabah", es: "Sabah", en: "Sabah"),
        Team(key: "Shajtar Donetsk", espnID: 493, abbr: "SHK", colorHex: 0xFF5900, country: "UA", domesticLeague: nil,
             ca: "Xakhtar Donetsk", es: "Shajtar Donetsk", en: "Shakhtar Donetsk"),
        Team(key: "Slavia de Praga", espnID: 494, abbr: "SLA", colorHex: 0xDC1F26, country: "CZ", domesticLeague: nil,
             ca: "Slàvia de Praga", es: "Slavia de Praga", en: "Slavia Prague"),
        Team(key: "Slovan Bratislava", espnID: 521, abbr: "SLO", colorHex: 0x3D7BC4, country: "SK", domesticLeague: nil,
             ca: "Slovan Bratislava", es: "Slovan Bratislava", en: "Slovan Bratislava"),
        Team(key: "Sporting de Portugal", espnID: 2250, abbr: "SCP", colorHex: 0x008127, country: "PT", domesticLeague: "por.1",
             ca: "Sporting de Portugal", es: "Sporting de Portugal", en: "Sporting CP"),
        Team(key: "Stuttgart", espnID: 134, abbr: "VFB", colorHex: 0xDA0308, country: "DE", domesticLeague: "ger.1",
             ca: "Stuttgart", es: "Stuttgart", en: "Stuttgart"),
        Team(key: "Viking", espnID: 510, abbr: "VIK", colorHex: 0x000080, country: "NO", domesticLeague: "nor.1",
             ca: "Viking", es: "Viking", en: "Viking"),
        Team(key: "Villarreal", espnID: 102, abbr: "VIL", colorHex: 0xE5B800, country: "ES", domesticLeague: "esp.1",
             ca: "Vila-real", es: "Villarreal", en: "Villarreal"),
    ]

    /// Índice por nombre canónico, construido una sola vez.
    private static let byKey: [String: Team] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.key, $0) }
    )

    /// Devuelve el club a partir de su nombre canónico.
    /// - Parameter key: Nombre tal como viene en el JSON.
    /// - Returns: El club, o `nil` si el nombre no está en el catálogo — algo
    ///   posible en las eliminatorias si UEFA repesca a un equipo que la app
    ///   todavía no conoce.
    static func team(_ key: String) -> Team? { byKey[key] }

    /// Nombre a mostrar para un equipo. Si no está en el catálogo devuelve la
    /// clave tal cual, que siempre es legible.
    static func name(_ key: String) -> String { byKey[key]?.displayName ?? key }

    /// Abreviatura del equipo, o las tres primeras letras si no se conoce.
    static func abbr(_ key: String) -> String {
        byKey[key]?.abbr ?? String(key.prefix(3)).uppercased()
    }

    /// Color del club, o un gris neutro si no está en el catálogo.
    static func color(_ key: String) -> Color {
        byKey[key]?.color ?? Color(hex: 0x6E7A96)
    }

    /// URL del escudo.
    static func badgeURL(_ key: String) -> URL? { byKey[key]?.badgeURL }

    /// Clubes ordenados por el nombre del idioma en curso, para los selectores.
    static var sortedForDisplay: [Team] {
        all.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
