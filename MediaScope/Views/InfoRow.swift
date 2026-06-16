import SwiftUI

struct InfoRow: View {
    let label: LocalizedStringKey
    let value: String?
    var monospaced: Bool = false
    var essential: Bool = false
    /// Si vrai, `value` est traité comme une clé de traduction (look-up via `\.locale` au render).
    var localizedValue: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(minWidth: 200, idealWidth: 220, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                if let value, !value.isEmpty {
                    if localizedValue {
                        Text(LocalizedStringKey(value))
                            .font(monospaced ? .body.monospaced() : .body)
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                    } else {
                        Text(value)
                            .font(monospaced ? .body.monospaced() : .body)
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct SectionCard<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.28), tint.opacity(0.14)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 34, height: 34)

                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.4), tint.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.18), Color.gray.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        )
        .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}

extension Color {
    static let mediaVideo = Color(red: 1.0, green: 0.42, blue: 0.21)
    static let mediaAudio = Color(red: 0.10, green: 0.65, blue: 1.0)
    static let mediaColor = Color(red: 0.95, green: 0.30, blue: 0.78)
    static let mediaTracks = Color(red: 0.95, green: 0.78, blue: 0.18)
    static let mediaMeta = Color(red: 0.30, green: 0.78, blue: 0.45)
    static let mediaTimecode = Color(red: 0.55, green: 0.40, blue: 0.95)
    static let mediaFile = Color(red: 0.55, green: 0.60, blue: 0.70)
    static let mediaSummary = Color(red: 0.20, green: 0.78, blue: 0.78)
}
