import SwiftUI

// MARK: - Helpers

nonisolated func formatSeconds(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "—" }
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    let ms = Int((seconds - Double(total)) * 1000)
    return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
}

// MARK: - Summary

struct SummarySection: View {
    let analysis: MediaAnalysis

    var body: some View {
        SectionCard(title: "Résumé", systemImage: "doc.text.magnifyingglass", tint: .mediaSummary) {
            InfoRow(label: "Nom du fichier", value: analysis.general.fileName, essential: true)
            InfoRow(label: "Conteneur", value: analysis.general.containerFormat, essential: true)
            InfoRow(label: "Taille", value: analysis.general.fileSizeFormatted, essential: true)
            InfoRow(label: "Durée", value: analysis.general.durationFormatted, monospaced: true, essential: true)
            InfoRow(label: "Débit global", value: analysis.general.overallBitrateFormatted, essential: true)
            InfoRow(label: "Encodeur", value: analysis.general.encoder)
            InfoRow(label: "Caméra / Application", value: analysis.general.writingApplication)
            if analysis.general.hasAlphaChannel {
                InfoRow(label: "Canal alpha", value: "Présent", localizedValue: true)
            }
            if let v = analysis.videoTracks.first {
                InfoRow(label: "Vidéo", value: "\(v.codecName) • \(v.resolutionLabel) • \(v.frameRateLabel)", essential: true)
            }
            if let a = analysis.audioTracks.first {
                InfoRow(label: "Audio", value: "\(a.codecName) • \(a.channelsLabel) • \(a.sampleRateLabel)", essential: true)
            }
        }
    }
}

// MARK: - Video

struct VideoSection: View {
    let track: VideoTrack
    let mode: ViewMode

    var body: some View {
        SectionCard(title: "Vidéo", systemImage: "film", tint: .mediaVideo) {
            InfoRow(label: "Codec", value: "\(track.codecName) (\(track.codecFourCC))", essential: true)
            InfoRow(label: "Nom long du codec", value: track.codecLongName)
            InfoRow(label: "Profil / Level", value: track.codecProfile, essential: true)
            InfoRow(label: "Résolution encodée", value: track.resolutionLabel, essential: true)
            InfoRow(label: "Résolution d'affichage", value: track.displayResolutionLabel)
            InfoRow(label: "Ratio d'aspect", value: track.aspectRatioLabel)
            InfoRow(label: "Pixel aspect ratio", value: track.pixelAspectRatio.map { String(format: "%.3f", $0) }, monospaced: true)
            InfoRow(label: "Fréquence d'images", value: track.frameRateLabel, monospaced: true, essential: true)
            InfoRow(label: "Mode du débit images", value: track.frameRateMode, localizedValue: true)
            InfoRow(label: "Débit estimé", value: track.bitrateLabel, essential: true)
            InfoRow(label: "Ordre des trames", value: track.fieldOrder, essential: true, localizedValue: true)
            InfoRow(label: "Espace de couleurs", value: track.colorSpace)
            InfoRow(label: "Mode de compression", value: track.compressionMode, localizedValue: true)
            if mode == .expert {
                InfoRow(label: "Profondeur par composante", value: track.bitDepth.map { "\($0) bits" })
                InfoRow(label: "Sous-échantillonnage", value: track.chromaSubsampling)
                InfoRow(label: "Pixel format", value: track.pixelFormat, monospaced: true)
                InfoRow(label: "Pixel format détaillé", value: track.pixelFormatDetailed, monospaced: true)
                InfoRow(label: "Profil Dolby Vision", value: track.dolbyVisionProfile)
                InfoRow(label: "Nombre total de frames", value: track.totalFrames.map { "\($0)" }, monospaced: true)
                InfoRow(label: "Bits / (Pixel × Image)", value: track.bitsPerPixelFrame.map { String(format: "%.3f", $0) }, monospaced: true)
                InfoRow(label: "Taille moyenne par frame", value: track.averageFrameSize.map {
                    ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                })
                InfoRow(label: "Durée de la piste", value: track.trackDuration.map { formatSeconds($0) }, monospaced: true)
                InfoRow(label: "Track ID", value: "\(track.trackID)", monospaced: true)
                if let mfd = track.minFrameDuration {
                    InfoRow(label: "Durée min. de frame", value: String(format: "%.6f s", mfd), monospaced: true)
                }
                if !track.trackMetadata.isEmpty {
                    Divider().padding(.vertical, 6)
                    Text("Métadonnées de piste")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    ForEach(track.trackMetadata) { item in
                        InfoRow(label: LocalizedStringKey(item.key), value: item.value)
                    }
                }
            }
        }
    }
}

// MARK: - Color

struct ColorSection: View {
    let track: VideoTrack

    var body: some View {
        SectionCard(title: "Colorimétrie", systemImage: "paintpalette", tint: .mediaColor) {
            InfoRow(label: "Primaries (gamut)", value: track.colorPrimaries, essential: true)
            InfoRow(label: "Fonction de transfert", value: track.transferFunction, essential: true)
            InfoRow(label: "Matrice YCbCr", value: track.yCbCrMatrix)
            InfoRow(label: "Plage de couleurs", value: track.colorRange, essential: true, localizedValue: true)
            HDRBadgeRow(isHDR: track.isHDR, format: track.hdrFormat)
            if track.isHDR {
                if let cll = track.maxCLL {
                    InfoRow(label: "MaxCLL", value: "\(cll) nits", monospaced: true)
                }
                if let fall = track.maxFALL {
                    InfoRow(label: "MaxFALL", value: "\(fall) nits", monospaced: true)
                }
                InfoRow(label: "Mastering Display Color Volume", value: track.hasMasteringDisplay ? "Présent" : "Absent", localizedValue: true)
            }
        }
    }
}

private struct HDRBadgeRow: View {
    let isHDR: Bool
    let format: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("HDR")
                .foregroundStyle(.secondary)
                .frame(width: 200, alignment: .leading)
            if isHDR {
                HStack(spacing: 6) {
                    Image(systemName: "sun.max.fill")
                        .font(.caption)
                    if let format {
                        Text(format)
                            .font(.callout.weight(.semibold))
                    } else {
                        Text("Oui")
                            .font(.callout.weight(.semibold))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.mediaColor.opacity(0.18))
                )
                .foregroundStyle(Color.mediaColor)
            } else {
                Text("Non")
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Audio

struct AudioSection: View {
    let track: AudioTrack
    let mode: ViewMode
    let index: Int

    var body: some View {
        SectionCard(title: "Audio \(index + 1)", systemImage: "waveform", tint: .mediaAudio) {
            InfoRow(label: "Codec", value: "\(track.codecName) (\(track.codecFourCC))", essential: true)
            InfoRow(label: "Codec ID (détaillé)", value: track.codecIDLong, monospaced: true)
            InfoRow(label: "Canaux", value: track.channelsLabel, essential: true, localizedValue: true)
            InfoRow(label: "Disposition des canaux", value: track.channelMap, monospaced: true, essential: true)
            InfoRow(label: "Fréquence d'échantillonnage", value: track.sampleRateLabel, monospaced: true, essential: true)
            InfoRow(label: "Quantification", value: track.bitsPerChannel.map { "\($0) bits" }, essential: true)
            InfoRow(label: "Débit estimé", value: track.bitrateLabel)
            InfoRow(label: "Format", value: track.isCompressed ? "Compressé" : "PCM non compressé", localizedValue: true)
            if !track.isCompressed {
                InfoRow(label: "Endianness", value: track.endianness, localizedValue: true)
            }
            InfoRow(label: "Profil audio", value: track.audioProfile)

            // Waveform si dispo
            if let peaks = track.waveformPeaks, !peaks.isEmpty {
                Spacer().frame(height: 8)
                WaveformView(peaks: peaks, tint: .mediaAudio, height: 48)
                    .padding(.vertical, 2)
            }

            // Mesures de loudness (LUFS + True Peak)
            if let lufs = track.integratedLUFS {
                InfoRow(label: "Loudness intégrée (LUFS)",
                        value: String(format: "%.1f LUFS", lufs),
                        monospaced: true)
            }
            if let tp = track.truePeakDBTP {
                InfoRow(label: "Crête vraie (dBTP)",
                        value: String(format: "%.1f dBTP", tp),
                        monospaced: true)
            }

            if mode == .expert {
                InfoRow(label: "Échantillons par frame", value: track.samplesPerFrame.map { "\($0) SPF" }, monospaced: true)
                InfoRow(label: "Nombre total d'échantillons", value: track.totalSamples.map { "\($0)" }, monospaced: true)
                InfoRow(label: "Durée de la piste", value: track.trackDuration.map { formatSeconds($0) }, monospaced: true)
                InfoRow(label: "Langue", value: track.language)
                InfoRow(label: "Track ID", value: "\(track.trackID)", monospaced: true)
                if !track.trackMetadata.isEmpty {
                    Divider().padding(.vertical, 6)
                    Text("Métadonnées de piste")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                    ForEach(track.trackMetadata) { item in
                        InfoRow(label: LocalizedStringKey(item.key), value: item.value)
                    }
                }
            }
        }
    }
}

// MARK: - Tracks summary

struct TracksSection: View {
    let analysis: MediaAnalysis

    var body: some View {
        SectionCard(title: "Pistes et flux", systemImage: "list.bullet.indent", tint: .mediaTracks) {
            InfoRow(label: "Pistes vidéo", value: "\(analysis.videoTracks.count)")
            InfoRow(label: "Pistes audio", value: "\(analysis.audioTracks.count)")
            InfoRow(label: "Sous-titres / CC", value: "\(analysis.subtitleTracks.count)")
            InfoRow(label: "Timecode", value: analysis.timecode != nil ? "Présent" : "Absent", localizedValue: true)
            ForEach(Array(analysis.subtitleTracks.enumerated()), id: \.element.id) { idx, sub in
                InfoRow(
                    label: "Sous-titre \(idx + 1)",
                    value: "\(sub.format)\(sub.language.map { " (\($0))" } ?? "")"
                )
            }
        }
    }
}

// MARK: - Timecode

struct TimecodeSection: View {
    let timecode: TimecodeInfo?
    let analysis: MediaAnalysis

    var body: some View {
        SectionCard(title: "Timecode", systemImage: "timer", tint: .mediaTimecode) {
            if let tc = timecode {
                InfoRow(label: "Source", value: "Piste TMCD intégrée", essential: true, localizedValue: true)
                InfoRow(label: "Timecode de départ", value: tc.startTimecode, monospaced: true, essential: true)
                InfoRow(label: "Timecode de fin", value: tc.endTimecode, monospaced: true, essential: true)
                InfoRow(label: "Fréquence", value: String(format: "%.3f fps", tc.frameRate), monospaced: true)
                InfoRow(label: "Drop frame", value: tc.dropFrame ? "Oui" : "Non", localizedValue: true)
                InfoRow(label: "Track ID", value: "\(tc.trackID)", monospaced: true)
            } else if let synth = syntheticTimecode() {
                InfoRow(label: "Source", value: "Calculé depuis la durée (pas de piste TMCD)", essential: true, localizedValue: true)
                InfoRow(label: "Timecode de départ", value: synth.start, monospaced: true, essential: true)
                InfoRow(label: "Timecode de fin", value: synth.end, monospaced: true, essential: true)
                InfoRow(label: "Fréquence", value: synth.rate, monospaced: true)
                InfoRow(label: "Drop frame", value: synth.dropFrame, localizedValue: true)
            } else {
                InfoRow(label: "Source", value: "Pas de timecode disponible", localizedValue: true)
            }
        }
    }

    private func syntheticTimecode() -> (start: String, end: String, rate: String, dropFrame: String)? {
        let fps = analysis.videoTracks.first?.nominalFrameRate ?? 0
        let duration = analysis.general.duration
        guard fps > 0, duration.isFinite, duration > 0 else { return nil }
        let fpsBase = max(1, Int(fps.rounded()))
        let totalDoubles = duration * Double(fps)
        guard totalDoubles.isFinite, totalDoubles < Double(Int.max) else { return nil }
        let totalFrames = Int(totalDoubles.rounded())
        let dropFrame = (abs(fps - 29.97) < 0.01 || abs(fps - 59.94) < 0.01)
        let sep = dropFrame ? ";" : ":"
        let h = totalFrames / (3600 * fpsBase)
        let m = (totalFrames % (3600 * fpsBase)) / (60 * fpsBase)
        let s = (totalFrames % (60 * fpsBase)) / fpsBase
        let f = totalFrames % fpsBase
        let end = String(format: "%02d:%02d:%02d\(sep)%02d", h, m, s, f)
        return (
            start: "00:00:00\(sep)00",
            end: end,
            rate: String(format: "%.3f fps", fps),
            dropFrame: dropFrame ? "Oui" : "Non"
        )
    }
}

// MARK: - Metadata

struct MetadataSection: View {
    let items: [MetadataItem]
    let mode: ViewMode

    var body: some View {
        SectionCard(title: "Métadonnées", systemImage: "tag", tint: .mediaMeta) {
            if items.isEmpty {
                InfoRow(label: "Aucune métadonnée", value: nil)
            } else {
                ForEach(displayed) { item in
                    InfoRow(
                        label: LocalizedStringKey(humanLabel(for: item.key)),
                        value: item.value
                    )
                }
            }
        }
    }

    private var displayed: [MetadataItem] {
        switch mode {
        case .simple:
            let priorityKeys: Set<String> = ["title", "artist", "albumName", "creationDate", "make", "model", "software", "copyrights"]
            let priority = items.filter { priorityKeys.contains($0.key) }
            return priority.isEmpty ? Array(items.prefix(8)) : priority
        case .expert:
            return items
        }
    }

    private func humanLabel(for key: String) -> String {
        switch key {
        case "title": return "Titre"
        case "artist": return "Artiste"
        case "albumName": return "Album"
        case "creationDate": return "Date de création"
        case "make": return "Fabricant"
        case "model": return "Modèle"
        case "software": return "Logiciel"
        case "copyrights": return "Droits d'auteur"
        case "description": return "Description"
        case "language": return "Langue"
        default: return key
        }
    }
}

// MARK: - MediaInfoLib statut (diagnostic)

struct MediaInfoStatusSection: View {
    var body: some View {
        SectionCard(title: "MediaInfo avancé — non disponible", systemImage: "exclamationmark.triangle", tint: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                if MediaInfoBridge.isAvailable {
                    Text("La bibliothèque est chargée mais n'a renvoyé aucune donnée pour ce fichier.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("La bibliothèque `libmediainfo.0.dylib` n'a pas pu être chargée. Suis les instructions de `INSTALL_MEDIAINFO.md`.")
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.vertical, 4)
                Text("Diagnostic dlopen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(MediaInfoBridge.diagnostics)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - MediaInfoLib (avancé)

struct MediaInfoSection: View {
    let data: MediaInfoData
    let mode: ViewMode

    var body: some View {
        SectionCard(title: "MediaInfo avancé", systemImage: "doc.badge.gearshape", tint: .mediaFile) {
            InfoRow(label: "Format", value: data.format)
            InfoRow(label: "Format / Profil", value: data.formatProfile, essential: true)
            InfoRow(label: "Codec ID", value: data.codecID, monospaced: true)
            InfoRow(label: "Encoded Library (x264, etc.)", value: data.encodedLibrary, essential: true)
            InfoRow(label: "Writing application", value: data.writingApplication, essential: true)
            InfoRow(label: "Writing library", value: data.writingLibrary)
            InfoRow(label: "Mode du débit (CBR / VBR)", value: data.bitRateMode, essential: true)
            InfoRow(label: "Stream size", value: data.streamSize)
            InfoRow(label: "Reference frames", value: data.referenceFrames, monospaced: true)
            InfoRow(label: "Format Level", value: data.formatLevel)
            InfoRow(label: "Chroma subsampling (MediaInfo)", value: data.chromaSubsampling)
            InfoRow(label: "Scan type", value: data.scanType)
            InfoRow(label: "Scan order", value: data.scanOrder)
            InfoRow(label: "Compression ratio", value: data.compressionRatio)

            if mode == .expert {
                rawDump(label: "Vidéo (tous champs)", items: data.extraVideo)
                rawDump(label: "Audio (tous champs)", items: data.extraAudio)
                rawDump(label: "Général (tous champs)", items: data.extraGeneral)
            }
        }
    }

    @ViewBuilder
    private func rawDump(label: LocalizedStringKey, items: [String: String]) -> some View {
        if !items.isEmpty {
            Divider().padding(.vertical, 6)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
            ForEach(items.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                InfoRow(label: LocalizedStringKey(k), value: v)
            }
        }
    }
}

// MARK: - File details (expert)

struct FileDetailsSection: View {
    let general: GeneralInfo

    var body: some View {
        SectionCard(title: "Détails fichier", systemImage: "info.circle", tint: .mediaFile) {
            InfoRow(label: "URL", value: general.fileURL.path, monospaced: true)
            InfoRow(label: "Extension", value: general.containerExtension)
            InfoRow(label: "UTI", value: general.utiType, monospaced: true)
            InfoRow(label: "Marque majeure (ftyp)", value: general.majorBrand, monospaced: true)
            if !general.compatibleBrands.isEmpty {
                InfoRow(
                    label: "Marques compatibles",
                    value: general.compatibleBrands.joined(separator: ", "),
                    monospaced: true
                )
            }
            InfoRow(label: "Création", value: general.creationDate.map { formatted($0) })
            InfoRow(label: "Modification", value: general.modificationDate.map { formatted($0) })
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - Capture (GPS + caméra)

struct CaptureSection: View {
    let analysis: MediaAnalysis

    var body: some View {
        SectionCard(title: "Capture", systemImage: "camera.viewfinder", tint: .mediaSummary) {
            if let c = analysis.camera {
                InfoRow(label: "Marque", value: c.make, essential: true)
                InfoRow(label: "Modèle", value: c.model, essential: true)
                InfoRow(label: "Logiciel embarqué", value: c.software)
                InfoRow(label: "Objectif", value: c.lensModel)
                InfoRow(label: "Date d'enregistrement", value: c.recordingDate.map { formatted($0) }, essential: true)
                if c.isLivePhoto == true {
                    InfoRow(label: "Format", value: "Live Photo / Live Video", localizedValue: true)
                }
            }
            if let gps = analysis.gpsLocation {
                InfoRow(label: "Coordonnées GPS", value: gps.formatted, monospaced: true, essential: true)
                if let url = gps.mapsURL {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("Carte")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 200, idealWidth: 220, alignment: .leading)
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                Text("Ouvrir dans Plans")
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            if analysis.camera == nil && analysis.gpsLocation == nil {
                InfoRow(label: "Aucune donnée de capture", value: nil)
            }
        }
    }

    private func formatted(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .medium
        return f.string(from: d)
    }
}

// MARK: - Chapitres

struct ChaptersSection: View {
    let chapters: [ChapterMarker]

    var body: some View {
        SectionCard(title: "Chapitres", systemImage: "list.number", tint: .mediaTracks) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chap in
                InfoRow(
                    label: LocalizedStringKey("Chapitre \(idx + 1)"),
                    value: chap.title.isEmpty
                        ? chap.startFormatted
                        : "\(chap.startFormatted) — \(chap.title)",
                    monospaced: true
                )
            }
        }
    }
}

// MARK: - Caractéristiques média + Finder/Spotlight (système macOS)

struct SystemMetadataSection: View {
    let analysis: MediaAnalysis
    let mode: ViewMode

    var body: some View {
        SectionCard(title: "Système macOS", systemImage: "applelogo", tint: .mediaFile) {
            if !analysis.finderTags.isEmpty {
                InfoRow(
                    label: "Tags Finder",
                    value: analysis.finderTags.joined(separator: ", ")
                )
            }
            if let comment = analysis.spotlightComment {
                InfoRow(label: "Commentaire Spotlight", value: comment)
            }
            if let source = analysis.downloadSource {
                InfoRow(label: "Source de téléchargement", value: source, monospaced: true)
            }
            if mode == .expert && !analysis.mediaCharacteristics.isEmpty {
                Divider().padding(.vertical, 6)
                Text("Caractéristiques AVMediaCharacteristics")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                ForEach(Array(analysis.mediaCharacteristics).sorted(), id: \.self) { c in
                    InfoRow(label: LocalizedStringKey(c), value: nil)
                }
            }
            if analysis.finderTags.isEmpty
                && analysis.spotlightComment == nil
                && analysis.downloadSource == nil
                && (analysis.mediaCharacteristics.isEmpty || mode != .expert) {
                InfoRow(label: "Aucune métadonnée macOS", value: nil)
            }
        }
    }
}

