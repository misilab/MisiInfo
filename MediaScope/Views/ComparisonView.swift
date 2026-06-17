import SwiftUI

/// Vue qui affiche deux analyses côte à côte avec mise en évidence des différences.
struct ComparisonView: View {
    let left: MediaAnalysis
    let right: MediaAnalysis

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                ComparisonCategory(title: "Général", rows: generalRows)
                ComparisonCategory(title: "Vidéo", rows: videoRows)
                ComparisonCategory(title: "Colorimétrie", rows: colorRows)
                ComparisonCategory(title: "Audio", rows: audioRows)
                ComparisonCategory(title: "Loudness", rows: loudnessRows)
                ComparisonCategory(title: "Timecode / Capture", rows: timecodeAndCaptureRows)

                summaryBadge
                Spacer(minLength: 16)
            }
            .padding(22)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            fileChip(label: "Fichier A", name: left.general.fileName, color: .blue)
            Image(systemName: "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(.secondary)
            fileChip(label: "Fichier B", name: right.general.fileName, color: .purple)
        }
        .padding(.bottom, 8)
    }

    private func fileChip(label: String, name: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(name)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.35), lineWidth: 0.7)
        )
    }

    // MARK: Rows

    private var generalRows: [ComparisonRow] {
        [
            ComparisonRow(label: "Conteneur", leftValue: left.general.containerFormat, rightValue: right.general.containerFormat),
            ComparisonRow(label: "Durée", leftValue: left.general.durationFormatted, rightValue: right.general.durationFormatted),
            ComparisonRow(label: "Taille", leftValue: left.general.fileSizeFormatted, rightValue: right.general.fileSizeFormatted),
            ComparisonRow(label: "Débit global", leftValue: left.general.overallBitrateFormatted ?? "—", rightValue: right.general.overallBitrateFormatted ?? "—"),
            ComparisonRow(label: "Encodeur", leftValue: left.general.encoder ?? "—", rightValue: right.general.encoder ?? "—")
        ]
    }

    private var videoRows: [ComparisonRow] {
        let l = left.videoTracks.first
        let r = right.videoTracks.first
        return [
            ComparisonRow(label: "Codec", leftValue: l?.codecName ?? "—", rightValue: r?.codecName ?? "—"),
            ComparisonRow(label: "Profil", leftValue: l?.codecProfile ?? "—", rightValue: r?.codecProfile ?? "—"),
            ComparisonRow(label: "Résolution", leftValue: l?.resolutionLabel ?? "—", rightValue: r?.resolutionLabel ?? "—"),
            ComparisonRow(label: "Fréquence d'images", leftValue: l?.frameRateLabel ?? "—", rightValue: r?.frameRateLabel ?? "—"),
            ComparisonRow(label: "Débit estimé", leftValue: l?.bitrateLabel ?? "—", rightValue: r?.bitrateLabel ?? "—"),
            ComparisonRow(label: "Profondeur", leftValue: l?.bitDepth.map { "\($0) bits" } ?? "—", rightValue: r?.bitDepth.map { "\($0) bits" } ?? "—"),
            ComparisonRow(label: "Sous-échantillonnage", leftValue: l?.chromaSubsampling ?? "—", rightValue: r?.chromaSubsampling ?? "—")
        ]
    }

    private var colorRows: [ComparisonRow] {
        let l = left.videoTracks.first
        let r = right.videoTracks.first
        return [
            ComparisonRow(label: "Primaries", leftValue: l?.colorPrimaries ?? "—", rightValue: r?.colorPrimaries ?? "—"),
            ComparisonRow(label: "Transfer", leftValue: l?.transferFunction ?? "—", rightValue: r?.transferFunction ?? "—"),
            ComparisonRow(label: "Matrice", leftValue: l?.yCbCrMatrix ?? "—", rightValue: r?.yCbCrMatrix ?? "—"),
            ComparisonRow(label: "HDR", leftValue: l?.isHDR == true ? (l?.hdrFormat ?? "Oui") : "Non", rightValue: r?.isHDR == true ? (r?.hdrFormat ?? "Oui") : "Non"),
            ComparisonRow(label: "MaxCLL", leftValue: l?.maxCLL.map { "\($0)" } ?? "—", rightValue: r?.maxCLL.map { "\($0)" } ?? "—"),
            ComparisonRow(label: "MaxFALL", leftValue: l?.maxFALL.map { "\($0)" } ?? "—", rightValue: r?.maxFALL.map { "\($0)" } ?? "—")
        ]
    }

    private var audioRows: [ComparisonRow] {
        let l = left.audioTracks.first
        let r = right.audioTracks.first
        return [
            ComparisonRow(label: "Codec", leftValue: l?.codecName ?? "—", rightValue: r?.codecName ?? "—"),
            ComparisonRow(label: "Canaux", leftValue: l?.channelsLabel ?? "—", rightValue: r?.channelsLabel ?? "—"),
            ComparisonRow(label: "Sample rate", leftValue: l?.sampleRateLabel ?? "—", rightValue: r?.sampleRateLabel ?? "—"),
            ComparisonRow(label: "Quantification", leftValue: l?.bitsPerChannel.map { "\($0) bits" } ?? "—", rightValue: r?.bitsPerChannel.map { "\($0) bits" } ?? "—"),
            ComparisonRow(label: "Débit", leftValue: l?.bitrateLabel ?? "—", rightValue: r?.bitrateLabel ?? "—")
        ]
    }

    private var loudnessRows: [ComparisonRow] {
        let l = left.audioTracks.first
        let r = right.audioTracks.first
        return [
            ComparisonRow(label: "LUFS intégré",
                          leftValue: l?.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—",
                          rightValue: r?.integratedLUFS.map { String(format: "%.1f LUFS", $0) } ?? "—"),
            ComparisonRow(label: "True Peak",
                          leftValue: l?.truePeakDBTP.map { String(format: "%.1f dBTP", $0) } ?? "—",
                          rightValue: r?.truePeakDBTP.map { String(format: "%.1f dBTP", $0) } ?? "—")
        ]
    }

    private var timecodeAndCaptureRows: [ComparisonRow] {
        [
            ComparisonRow(label: "TC de départ",
                          leftValue: left.timecode?.startTimecode ?? "—",
                          rightValue: right.timecode?.startTimecode ?? "—"),
            ComparisonRow(label: "TC de fin",
                          leftValue: left.timecode?.endTimecode ?? "—",
                          rightValue: right.timecode?.endTimecode ?? "—"),
            ComparisonRow(label: "Caméra",
                          leftValue: left.camera.map { ([$0.make, $0.model].compactMap { $0 }).joined(separator: " ") } ?? "—",
                          rightValue: right.camera.map { ([$0.make, $0.model].compactMap { $0 }).joined(separator: " ") } ?? "—"),
            ComparisonRow(label: "GPS",
                          leftValue: left.gpsLocation?.formatted ?? "—",
                          rightValue: right.gpsLocation?.formatted ?? "—")
        ]
    }

    private var allRows: [ComparisonRow] {
        generalRows + videoRows + colorRows + audioRows + loudnessRows + timecodeAndCaptureRows
    }

    private var summaryBadge: some View {
        let total = allRows.count
        let diff = allRows.filter { $0.differs }.count
        let color: Color = diff == 0 ? .green : (diff <= 3 ? .orange : .red)
        return HStack(spacing: 12) {
            Image(systemName: diff == 0 ? "checkmark.seal.fill" : "arrow.left.arrow.right")
                .font(.title2)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                if diff == 0 {
                    Text("Les deux fichiers sont identiques sur tous les champs comparés.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                } else {
                    Text("\(diff) différence\(diff > 1 ? "s" : "") sur \(total) champs comparés")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
                Text("Les lignes différentes sont surlignées et marquées d'un ⚠.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.12))
        )
        .padding(.top, 8)
    }
}

// MARK: - Row + Category

struct ComparisonRow: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let leftValue: String
    let rightValue: String

    var differs: Bool {
        // Considère "—" comme "même" si les deux le sont
        if leftValue == rightValue { return false }
        return true
    }
}

private struct ComparisonCategory: View {
    let title: LocalizedStringKey
    let rows: [ComparisonRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline.weight(.semibold))
                .padding(.horizontal, 12)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    ComparisonRowView(row: row)
                    if row.id != rows.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.3), lineWidth: 0.5)
            )
        }
    }
}

private struct ComparisonRowView: View {
    let row: ComparisonRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 4) {
                if row.differs {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(LocalizedStringKey(row.label))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 200, alignment: .leading)

            Text(row.leftValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(row.differs ? .orange : .primary)
                .textSelection(.enabled)

            Text(row.rightValue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(row.differs ? .orange : .primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(row.differs ? Color.orange.opacity(0.08) : Color.clear)
    }
}
