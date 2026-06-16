import SwiftUI

/// Logo principal utilisé pour la marque visuelle et la génération de l'AppIcon.
/// Direction : Pro dark — fond profond + accent cyan néon, style studio/étalonnage.
struct AppLogoView: View {
    var cornerStyle: RoundedCornerStyle = .continuous

    private let accent = Color(red: 0.15, green: 0.95, blue: 1.00)
    private let accentSoft = Color(red: 0.50, green: 0.98, blue: 1.00)

    var body: some View {
        ZStack {
            // Fond bleu nuit profond avec léger gradient de profondeur
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.06, green: 0.09, blue: 0.16), location: 0.0),
                    .init(color: Color(red: 0.02, green: 0.04, blue: 0.09), location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Halo cyan diffus en haut à droite (signal lumineux)
            RadialGradient(
                colors: [accent.opacity(0.35), .clear],
                center: UnitPoint(x: 0.78, y: 0.22),
                startRadius: 0,
                endRadius: 600
            )
            .blendMode(.screen)

            // Léger grain bleu en bas à gauche pour ancrer
            RadialGradient(
                colors: [Color(red: 0.0, green: 0.15, blue: 0.30).opacity(0.6), .clear],
                center: UnitPoint(x: 0.15, y: 0.85),
                startRadius: 0,
                endRadius: 500
            )

            // Symbole central : viseur + signal
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    // Anneau extérieur fin (viseur / scope)
                    Circle()
                        .strokeBorder(accent, lineWidth: s * 0.025)
                        .frame(width: s * 0.66, height: s * 0.66)
                        .shadow(color: accent.opacity(0.6), radius: s * 0.04)

                    // Anneau intérieur encore plus fin
                    Circle()
                        .strokeBorder(accent.opacity(0.45), lineWidth: s * 0.012)
                        .frame(width: s * 0.48, height: s * 0.48)

                    // Croix de viseur subtile (lignes courtes haut/bas/gauche/droite)
                    crosshair(size: s)

                    // Trait de scan horizontal — le "signal" qui passe
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, accentSoft, accentSoft, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: s * 0.78, height: s * 0.018)
                        .shadow(color: accent.opacity(0.9), radius: s * 0.015)

                    // Point central lumineux (lock-on)
                    Circle()
                        .fill(accentSoft)
                        .frame(width: s * 0.04, height: s * 0.04)
                        .shadow(color: accent, radius: s * 0.02)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadiusForSize, style: cornerStyle))
    }

    @ViewBuilder
    private func crosshair(size s: CGFloat) -> some View {
        ZStack {
            // Tiret haut
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(width: s * 0.012, height: s * 0.06)
                .offset(y: -s * 0.36)
            // Tiret bas
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(width: s * 0.012, height: s * 0.06)
                .offset(y: s * 0.36)
            // Tiret gauche
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(width: s * 0.06, height: s * 0.012)
                .offset(x: -s * 0.36)
            // Tiret droit
            Rectangle()
                .fill(accent.opacity(0.55))
                .frame(width: s * 0.06, height: s * 0.012)
                .offset(x: s * 0.36)
        }
    }

    private var cornerRadiusForSize: CGFloat {
        220
    }
}

/// Variante compacte pour l'UI (pas de coins arrondis fixes).
struct BrandMark: View {
    var size: CGFloat = 96

    var body: some View {
        AppLogoView()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: size * 0.04, y: size * 0.02)
    }
}

#Preview("Logo 512") {
    AppLogoView()
        .frame(width: 512, height: 512)
        .padding(40)
        .background(.gray.opacity(0.1))
}

#Preview("BrandMark grid") {
    HStack(spacing: 20) {
        BrandMark(size: 64)
        BrandMark(size: 96)
        BrandMark(size: 128)
        BrandMark(size: 256)
    }
    .padding(40)
}
