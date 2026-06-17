import SwiftUI

/// Section UI affichant le résultat d'un préréglage de conformité.
struct ConformitySection: View {
    let analysis: MediaAnalysis
    @Binding var selectedPresetID: String?

    private var selectedPreset: ConformityPreset? {
        guard let id = selectedPresetID else { return nil }
        return ConformityPresets.allBuiltIn.first { $0.id == id }
    }

    private var results: [ConformityResult] {
        guard let preset = selectedPreset else { return [] }
        return ConformityChecker.evaluate(analysis, against: preset)
    }

    private var score: Double {
        ConformityChecker.score(results)
    }

    private var criticalFailures: Int {
        ConformityChecker.criticalFailures(results)
    }

    private var overallColor: Color {
        if criticalFailures > 0 { return .red }
        if score < 100 { return .orange }
        return .green
    }

    var body: some View {
        SectionCard(title: "Conformité", systemImage: "checkmark.seal.fill", tint: .mediaColor) {
            // Sélecteur de preset
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Préréglage")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 200, alignment: .leading)
                Picker("Préréglage", selection: $selectedPresetID) {
                    Text("Aucun").tag(nil as String?)
                    ForEach(ConformityPresets.allBuiltIn) { preset in
                        Text(preset.name).tag(preset.id as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                Spacer()
            }
            .padding(.vertical, 4)

            if let preset = selectedPreset {
                // Résumé du preset
                Text(preset.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)

                // Score global
                scoreBadge

                Divider().padding(.vertical, 6)

                // Liste des règles
                ForEach(results) { result in
                    ConformityRuleRow(result: result)
                }
            } else {
                Text("Sélectionnez un préréglage pour valider la conformité du fichier.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            }
        }
    }

    private var scoreBadge: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(overallColor.opacity(0.2), lineWidth: 6)
                    .frame(width: 64, height: 64)
                if score > 0 {
                    Circle()
                        .trim(from: 0, to: score / 100)
                        .stroke(overallColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: -2) {
                    Text(String(format: "%.0f", score))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(overallColor)
                    Text("/100")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if criticalFailures > 0 {
                    Label("\(criticalFailures) non-conformité critique", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.weight(.semibold))
                } else if score >= 100 {
                    Label("Conforme à 100 %", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.weight(.semibold))
                } else {
                    Label("Conforme partiellement", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline.weight(.semibold))
                }
                Text("\(results.filter { $0.status == .pass }.count) / \(results.filter { $0.status != .notApplicable }.count) règles satisfaites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct ConformityRuleRow: View {
    let result: ConformityResult

    private var icon: (name: String, color: Color) {
        switch result.status {
        case .pass: return ("checkmark.circle.fill", .green)
        case .fail: return result.severity == .mandatory ? ("xmark.octagon.fill", .red) : ("exclamationmark.triangle.fill", .orange)
        case .warning: return ("exclamationmark.triangle.fill", .orange)
        case .notApplicable: return ("minus.circle", .secondary)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon.name)
                .font(.body)
                .foregroundStyle(icon.color)
                .frame(width: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(LocalizedStringKey(result.ruleTitle))
                        .font(.body.weight(.semibold))
                    severityBadge
                    Spacer()
                }
                HStack(spacing: 12) {
                    Text("Attendu : ")
                        .foregroundStyle(.secondary)
                        .font(.caption) +
                    Text(LocalizedStringKey(result.expected))
                        .foregroundStyle(.primary)
                        .font(.caption)
                }
                HStack(spacing: 12) {
                    Text("Actuel : ")
                        .foregroundStyle(.secondary)
                        .font(.caption) +
                    Text(result.actual)
                        .foregroundStyle(icon.color)
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                if result.status != .pass {
                    Text(LocalizedStringKey(result.explanation))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var severityBadge: some View {
        let (label, color): (String, Color) = {
            switch result.severity {
            case .mandatory: return ("OBLIGATOIRE", .red)
            case .recommended: return ("RECOMMANDÉ", .orange)
            case .informational: return ("INFO", .blue)
            }
        }()
        Text(LocalizedStringKey(label))
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}
