import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AnalysisDetailView: View {
    let item: MediaItem?
    let mode: ViewMode

    var body: some View {
        Group {
            if let item {
                content(for: item)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                EmptyDetailView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: item?.id)
    }

    @ViewBuilder
    private func content(for item: MediaItem) -> some View {
        switch item.state {
        case .pending, .analyzing:
            AnalysingView(name: item.displayName)
        case .failed(let message):
            FailureView(message: message)
        case .ready(let analysis):
            AnalysisReportView(analysis: analysis, mode: mode)
        }
    }
}

// MARK: - States

private struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 24) {
            BrandMark(size: 128)
            VStack(spacing: 8) {
                Text("MisiInfo")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Analyse technique de fichiers audio & vidéo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("Glissez un fichier dans la fenêtre ou utilisez ⌘O.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            CreditLine()
                .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct CreditLine: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("Créé par Matthieu Misiraca —")
            Link("www.misiraca.com", destination: URL(string: "https://www.misiraca.com")!)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }
}

private struct AnalysingView: View {
    let name: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Analyse de « \(name) »…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FailureView: View {
    let message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Analyse impossible")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Report

struct AnalysisReportView: View {
    let analysis: MediaAnalysis
    let mode: ViewMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                summaryGrid

                ForEach(Array(analysis.videoTracks.enumerated()), id: \.element.id) { _, track in
                    VideoSection(track: track, mode: mode)
                    ColorSection(track: track)
                }

                ForEach(Array(analysis.audioTracks.enumerated()), id: \.element.id) { idx, track in
                    AudioSection(track: track, mode: mode, index: idx)
                }

                TimecodeSection(timecode: analysis.timecode, analysis: analysis)

                TracksSection(analysis: analysis)
                MetadataSection(items: analysis.metadata, mode: mode)

                if let mi = analysis.mediaInfo, !mi.isEmpty {
                    MediaInfoSection(data: mi, mode: mode)
                } else if mode == .expert {
                    MediaInfoStatusSection()
                }

                if mode == .expert {
                    FileDetailsSection(general: analysis.general)
                }

                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .background(Color.clear)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                // Vignette du premier frame si dispo, sinon BrandMark
                if let posterData = analysis.videoTracks.first?.posterFrame {
                    PosterFrameView(data: posterData, maxWidth: 200)
                } else {
                    BrandMark(size: 64)
                        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(analysis.general.fileName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    metaPills
                }
                Spacer()
                actionButtons
            }
        }
        .padding(.bottom, 6)
    }

    private var metaPills: some View {
        HStack(spacing: 6) {
            Pill(text: analysis.general.containerExtension, color: .mediaSummary)
            if let v = analysis.videoTracks.first {
                Pill(text: v.codecName, color: .mediaVideo)
                Pill(text: v.resolutionLabel, color: .mediaVideo.opacity(0.7))
                if v.isHDR { Pill(text: v.hdrFormat ?? "HDR", color: .mediaColor) }
            }
            if let a = analysis.audioTracks.first {
                Pill(text: a.codecName, color: .mediaAudio)
                Pill(text: a.channelsLabel, color: .mediaAudio.opacity(0.7))
            }
        }
    }

    private var summaryGrid: some View {
        HStack(spacing: 10) {
            StatTile(title: "Durée", value: analysis.general.durationFormatted, systemImage: "clock", tint: .mediaSummary, monospaced: true)
            StatTile(title: "Taille", value: analysis.general.fileSizeFormatted, systemImage: "internaldrive", tint: .mediaFile)
            StatTile(title: "Débit", value: analysis.general.overallBitrateFormatted ?? "—", systemImage: "speedometer", tint: .mediaAudio)
            if let v = analysis.videoTracks.first {
                StatTile(title: "FPS", value: v.frameRateLabel, systemImage: "film.stack", tint: .mediaVideo, monospaced: true)
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([analysis.general.fileURL])
            } label: {
                Label("Révéler", systemImage: "folder")
            }
            .help("Révéler dans le Finder")

            Button {
                let text = ReportExporter.text(for: analysis)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(text, forType: .string)
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
            .help("Copier le rapport texte")

            Menu {
                Button("Exporter en texte (.txt)") { exportReport() }
                Button("Exporter en PDF (.pdf)") { exportPDFReport() }
            } label: {
                Label("Exporter", systemImage: "square.and.arrow.up")
            }
            .menuIndicator(.hidden)
            .help("Exporter le rapport")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
    }

    private func exportPDFReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = analysis.general.fileURL.deletingPathExtension().lastPathComponent + "-MisiInfo.pdf"
        panel.canCreateDirectories = true
        panel.title = "Exporter le rapport PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !PDFReportGenerator.generate(analysis, to: url) {
            let alert = NSAlert()
            alert.messageText = "Échec de génération du PDF"
            alert.runModal()
        }
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = analysis.general.fileURL.deletingPathExtension().lastPathComponent + "-MisiInfo.txt"
        panel.title = "Exporter le rapport"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = ReportExporter.text(for: analysis)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

// MARK: - Pills & Tiles

private struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            )
            .overlay(
                Capsule().strokeBorder(color.opacity(0.30), lineWidth: 0.6)
            )
            .foregroundStyle(color)
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    let systemImage: String
    let tint: Color
    var monospaced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(tint.opacity(0.15))
                    )
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Text(value)
                .font(monospaced
                    ? .title2.monospacedDigit().weight(.bold)
                    : .title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [tint.opacity(0.30), tint.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        )
        .shadow(color: tint.opacity(0.08), radius: 4, x: 0, y: 1)
    }
}
