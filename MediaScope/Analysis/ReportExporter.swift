import Foundation

nonisolated enum ReportExporter {

    static func text(for analysis: MediaAnalysis) -> String {
        var b = Builder()
        b.title("MisiInfo — Rapport d'analyse")
        b.blank()

        b.section("Résumé")
        b.kv("Nom du fichier", analysis.general.fileName)
        b.kv("Conteneur", analysis.general.containerFormat)
        b.kv("Extension", analysis.general.containerExtension)
        b.kv("Taille", analysis.general.fileSizeFormatted)
        b.kv("Durée", analysis.general.durationFormatted)
        b.kv("Débit global", analysis.general.overallBitrateFormatted ?? "—")
        if let c = analysis.general.creationDate { b.kv("Création", Self.date(c)) }
        if let m = analysis.general.modificationDate { b.kv("Modification", Self.date(m)) }
        b.kv("Chemin", analysis.general.fileURL.path)
        b.blank()

        for (i, v) in analysis.videoTracks.enumerated() {
            b.section("Vidéo \(i + 1)")
            b.kv("Codec", "\(v.codecName) (\(v.codecFourCC))")
            b.kv("Résolution encodée", v.resolutionLabel)
            b.kv("Résolution d'affichage", v.displayResolutionLabel)
            b.kv("Ratio d'aspect", v.aspectRatioLabel)
            b.kv("Fréquence d'images", v.frameRateLabel)
            b.kv("Débit estimé", v.bitrateLabel ?? "—")
            b.kv("Profondeur par composante", v.bitDepth.map { "\($0) bits" } ?? "—")
            b.kv("Sous-échantillonnage", v.chromaSubsampling ?? "—")
            b.kv("Track ID", "\(v.trackID)")
            b.blank()

            b.section("Colorimétrie (Vidéo \(i + 1))")
            b.kv("Primaries (gamut)", v.colorPrimaries ?? "—")
            b.kv("Fonction de transfert", v.transferFunction ?? "—")
            b.kv("Matrice YCbCr", v.yCbCrMatrix ?? "—")
            b.kv("HDR", v.isHDR ? (v.hdrFormat ?? "Oui") : "Non")
            b.blank()
        }

        for (i, a) in analysis.audioTracks.enumerated() {
            b.section("Audio \(i + 1)")
            b.kv("Codec", "\(a.codecName) (\(a.codecFourCC))")
            b.kv("Canaux", a.channelsLabel)
            b.kv("Fréquence d'échantillonnage", a.sampleRateLabel)
            b.kv("Quantification", a.bitsPerChannel.map { "\($0) bits" } ?? "—")
            b.kv("Débit estimé", a.bitrateLabel ?? "—")
            b.kv("Format", a.isCompressed ? "Compressé" : "PCM non compressé")
            b.kv("Langue", a.language ?? "—")
            b.kv("Track ID", "\(a.trackID)")
            b.blank()
        }

        if !analysis.subtitleTracks.isEmpty {
            b.section("Sous-titres / Closed Captions")
            for (i, s) in analysis.subtitleTracks.enumerated() {
                b.kv("Piste \(i + 1)", "\(s.format)\(s.language.map { " (\($0))" } ?? "")\(s.isClosedCaption ? " — CC" : "")")
            }
            b.blank()
        }

        if let tc = analysis.timecode {
            b.section("Timecode")
            b.kv("Timecode de départ", tc.startTimecode ?? "—")
            b.kv("Fréquence", String(format: "%.3f fps", tc.frameRate))
            b.kv("Drop frame", tc.dropFrame ? "Oui" : "Non")
            b.kv("Track ID", "\(tc.trackID)")
            b.blank()
        }

        b.section("Pistes et flux")
        b.kv("Pistes vidéo", "\(analysis.videoTracks.count)")
        b.kv("Pistes audio", "\(analysis.audioTracks.count)")
        b.kv("Sous-titres / CC", "\(analysis.subtitleTracks.count)")
        b.kv("Timecode", analysis.timecode != nil ? "Présent" : "Absent")
        b.blank()

        if !analysis.metadata.isEmpty {
            b.section("Métadonnées")
            for item in analysis.metadata {
                let prefix = item.keySpace.map { "[\($0)] " } ?? ""
                b.kv("\(prefix)\(item.key)", item.value)
            }
            b.blank()
        }

        b.line("Généré par MisiInfo — \(Self.date(Date()))")
        return b.output
    }

    private static func date(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f.string(from: date)
    }

    private struct Builder {
        var output: String = ""
        mutating func title(_ s: String) {
            output += "=== \(s) ===\n"
        }
        mutating func section(_ s: String) {
            output += "— \(s)\n"
        }
        mutating func kv(_ key: String, _ value: String) {
            output += "  \(key.padding(toLength: 32, withPad: " ", startingAt: 0)) \(value)\n"
        }
        mutating func line(_ s: String) { output += "\(s)\n" }
        mutating func blank() { output += "\n" }
    }
}
