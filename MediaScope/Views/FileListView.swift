import SwiftUI
import AppKit

struct FileListView: View {
    @Bindable var library: MediaLibrary

    var body: some View {
        Group {
            if library.items.isEmpty {
                emptyState
            } else {
                List(selection: $library.selectionID) {
                    Section {
                        ForEach(library.items) { item in
                            FileRow(item: item)
                                .tag(item.id)
                                .contextMenu {
                                    Button("Révéler dans le Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                    }
                                    Button("Réanalyser") { library.reanalyze(itemID: item.id) }
                                    Divider()
                                    Button("Retirer", role: .destructive) { library.remove(itemID: item.id) }
                                }
                        }
                    } header: {
                        Text("\(library.items.count) fichier(s)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("MisiInfo")
        .animation(.easeInOut(duration: 0.2), value: library.items.count)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            BrandMark(size: 96)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("MisiInfo")
                    .font(.title3.weight(.semibold))
                Text("Glissez un fichier audio ou vidéo ici\npour démarrer l'analyse.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            CreditLine()
                .padding(.bottom, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FileRow: View {
    let item: MediaItem

    var body: some View {
        HStack(spacing: 12) {
            iconBadge
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            trailingAccessory
        }
        .padding(.vertical, 4)
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(iconTint.opacity(0.18))
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconTint)
        }
        .frame(width: 32, height: 32)
    }

    private var iconName: String {
        switch item.state {
        case .failed: return "exclamationmark.triangle.fill"
        default:
            return isAudio ? "waveform" : "film.fill"
        }
    }

    private var iconTint: Color {
        switch item.state {
        case .failed: return .orange
        default:
            return isAudio ? .mediaAudio : .mediaVideo
        }
    }

    private var isAudio: Bool {
        let ext = item.url.pathExtension.lowercased()
        return ["wav", "aif", "aiff", "mp3", "flac", "m4a", "aac", "caf", "ogg"].contains(ext)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        switch item.state {
        case .analyzing:
            ProgressView()
                .controlSize(.small)
        case .ready(let analysis):
            if let v = analysis.videoTracks.first, v.isHDR {
                Text("HDR")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.mediaColor))
            }
        default:
            EmptyView()
        }
    }

    private var statusText: Text {
        switch item.state {
        case .pending: return Text("En attente…")
        case .analyzing: return Text("Analyse en cours…")
        case .ready(let analysis):
            if let v = analysis.videoTracks.first {
                return Text("\(v.resolutionLabel) • \(v.codecName)")
            } else if let a = analysis.audioTracks.first {
                return Text("\(a.codecName) • \(a.sampleRateLabel)")
            } else {
                return Text(analysis.general.containerFormat)
            }
        case .failed(let msg): return Text("Échec : \(msg)")
        }
    }
}
