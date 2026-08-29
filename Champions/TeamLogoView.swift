//
//  TeamLogoView.swift
//  Champions
//

import SwiftUI

/// Escudo de un club, descargado del CDN de ESPN.
///
/// Si el escudo no llega —red caída, club fuera del catálogo— se dibujan las
/// iniciales sobre el color del club. Es un recurso que envejece bien: nunca
/// deja un hueco vacío y siempre identifica al equipo.
struct TeamLogoView: View {
    let teamName: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url = Teams.badgeURL(teamName) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure, .empty:
                        initials
                    @unknown default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(Teams.name(teamName)))
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Teams.color(teamName).opacity(0.25))
            Text(Teams.abbr(teamName).prefix(3))
                .font(.system(size: size * 0.30, weight: .bold))
                .foregroundStyle(Teams.color(teamName))
                .minimumScaleFactor(0.6)
        }
    }
}

#Preview {
    VStack(spacing: 30) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 18) {
            ForEach(Teams.all.prefix(12)) { team in
                VStack(spacing: 6) {
                    TeamLogoView(teamName: team.key, size: 44)
                    Text(team.abbr).font(.caption2).foregroundStyle(.white)
                }
            }
        }
        .padding()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(hex: 0x080B16))
}
