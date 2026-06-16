import SwiftUI

/// Visualisation simple d'un waveform audio à partir d'une liste de crêtes normalisées 0..1.
struct WaveformView: View {
    let peaks: [Float]
    var tint: Color = .mediaAudio
    var height: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                guard !peaks.isEmpty, size.width > 0, size.height > 0 else { return }
                let w = size.width
                let h = size.height
                let mid = h / 2
                let barW = max(1.0, w / CGFloat(max(peaks.count, 1)))
                let gap = barW > 2 ? barW * 0.25 : 0
                for (i, p) in peaks.enumerated() {
                    let amp = max(2, CGFloat(p) * h)
                    let x = CGFloat(i) * barW
                    let rect = CGRect(x: x, y: mid - amp / 2, width: barW - gap, height: amp)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 4),
                             with: .color(tint.opacity(0.85)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
        )
    }
}

/// Vignette du premier frame avec coins arrondis + ombre subtile.
struct PosterFrameView: View {
    let data: Data
    var maxWidth: CGFloat = 240

    var body: some View {
        if let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth, maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.6)
                )
                .shadow(color: .black.opacity(0.20), radius: 8, y: 3)
        }
    }
}
