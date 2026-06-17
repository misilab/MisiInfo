import Foundation
import AVFoundation
import CoreMedia

// MARK: - CLI principal

@main
struct MisiInfoCLI {
    static func main() async {
        let args = CommandLine.arguments.dropFirst()
        if args.contains("--help") || args.contains("-h") || args.isEmpty {
            printUsage()
            exit(0)
        }

        var jsonOutput = false
        var pretty = true
        var checkPreset: String? = nil
        var paths: [String] = []

        var iter = args.makeIterator()
        while let arg = iter.next() {
            switch arg {
            case "--json": jsonOutput = true
            case "--compact": pretty = false
            case "--check":
                checkPreset = iter.next()
            default:
                paths.append(arg)
            }
        }

        guard !paths.isEmpty else {
            fputs("Erreur : aucun fichier fourni.\n", stderr)
            printUsage()
            exit(64)
        }

        var hadAnalysisError = false
        var hadCriticalFailure = false

        for path in paths {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                fputs("Fichier introuvable : \(url.path)\n", stderr)
                hadAnalysisError = true
                continue
            }
            do {
                let info = try await CLIAnalyzer.analyze(url: url)
                if jsonOutput {
                    let data = try JSONEncoder.misiinfo(pretty: pretty).encode(info)
                    if let s = String(data: data, encoding: .utf8) { print(s) }
                } else {
                    CLIPrinter.printSummary(info)
                }
                if let preset = checkPreset {
                    let results = CLIConformity.check(info, preset: preset)
                    CLIPrinter.printConformity(presetID: preset, results: results)
                    if results.contains(where: { $0.severity == "mandatory" && $0.status == "fail" }) {
                        hadCriticalFailure = true
                    }
                }
            } catch {
                fputs("Erreur d'analyse \(url.lastPathComponent) : \(error.localizedDescription)\n", stderr)
                hadAnalysisError = true
            }
        }

        // Flush + exit code agrégé : priorité critical > error > OK
        fflush(stdout)
        fflush(stderr)
        if hadCriticalFailure { exit(2) }
        if hadAnalysisError { exit(1) }
    }

    static func printUsage() {
        print("""
        misiinfo — analyse technique de fichiers audio/vidéo (en ligne de commande)

        USAGE :
          misiinfo [OPTIONS] <fichier> [<fichier2>...]

        OPTIONS :
          --json              Sortie JSON (par défaut : texte lisible)
          --compact           JSON minifié (sans pretty-print)
          --check <preset>    Valide la conformité à un préréglage
                              (netflix.4k.hdr10, netflix.4k.sdr, broadcast.ebu.r128,
                               dcp.feature, youtube.4k, prores.422hq, web.html5)
          -h, --help          Affiche cette aide

        EXEMPLES :
          misiinfo video.mp4
          misiinfo --json clip.mov > rapport.json
          misiinfo --check broadcast.ebu.r128 livraison.wav
          misiinfo --json --check netflix.4k.hdr10 master.mxf

        Code retour :
          0 = OK / conforme
          1 = erreur d'analyse
          2 = non-conformité critique (avec --check)
         64 = erreur d'arguments
        """)
    }
}

// MARK: - Analyzer

struct CLIInfo: Codable {
    var general: General
    var video: Video?
    var audio: Audio?

    struct General: Codable {
        var fileName: String
        var fileSize: Int64
        var container: String
        var duration: Double
        var overallBitrate: Int64?
    }
    struct Video: Codable {
        var codecName: String
        var codecFourCC: String
        var width: Int
        var height: Int
        var nominalFrameRate: Double
        var bitDepth: Int?
        var estimatedDataRate: Double?
        var colorPrimaries: String?
        var transferFunction: String?
        var matrix: String?
        var chromaSubsampling: String?
    }
    struct Audio: Codable {
        var codecName: String
        var codecFourCC: String
        var channelCount: Int
        var sampleRate: Double
        var bitsPerChannel: Int?
        var estimatedDataRate: Double?
    }
}

enum CLIAnalyzer {
    static func analyze(url: URL) async throws -> CLIInfo {
        let asset = AVURLAsset(url: url)
        let (duration, allTracks) = try await (asset.load(.duration), asset.load(.tracks))
        let durSec = CMTimeGetSeconds(duration)
        let attrs = try url.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(attrs.fileSize ?? 0)
        let overall: Int64? = (durSec > 0 && size > 0) ? Int64(Double(size) * 8 / durSec) : nil

        var info = CLIInfo(general: .init(
            fileName: url.lastPathComponent,
            fileSize: size,
            container: containerLabel(ext: url.pathExtension),
            duration: durSec,
            overallBitrate: overall
        ), video: nil, audio: nil)

        for track in allTracks {
            switch track.mediaType {
            case .video:
                let descs = try await track.load(.formatDescriptions)
                guard let f = descs.first else { continue }
                let st = CMFormatDescriptionGetMediaSubType(f)
                let dims = CMVideoFormatDescriptionGetDimensions(f)
                let fps = try await track.load(.nominalFrameRate)
                let rate = try await track.load(.estimatedDataRate)
                let exts = CMFormatDescriptionGetExtensions(f) as? [String: Any] ?? [:]
                let prim = exts[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
                let trf = exts[kCMFormatDescriptionExtension_TransferFunction as String] as? String
                let mtx = exts[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
                let dep = (exts[kCMFormatDescriptionExtension_Depth as String] as? NSNumber)?.intValue
                let perComp = dep.map { d -> Int in d / 3 }
                let fourCC = fourCCString(st)
                info.video = .init(
                    codecName: longCodecName(fourCC),
                    codecFourCC: fourCC,
                    width: Int(dims.width),
                    height: Int(dims.height),
                    nominalFrameRate: Double(fps),
                    bitDepth: perComp,
                    estimatedDataRate: Double(rate),
                    colorPrimaries: prim,
                    transferFunction: trf,
                    matrix: mtx,
                    chromaSubsampling: chromaFor(fourCC: fourCC)
                )
            case .audio:
                let descs = try await track.load(.formatDescriptions)
                guard let f = descs.first else { continue }
                let st = CMFormatDescriptionGetMediaSubType(f)
                let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(f)?.pointee
                let rate = try await track.load(.estimatedDataRate)
                let fourCC = fourCCString(st)
                info.audio = .init(
                    codecName: longCodecName(fourCC),
                    codecFourCC: fourCC,
                    channelCount: Int(asbd?.mChannelsPerFrame ?? 0),
                    sampleRate: asbd?.mSampleRate ?? 0,
                    bitsPerChannel: (asbd?.mBitsPerChannel).flatMap { $0 > 0 ? Int($0) : nil },
                    estimatedDataRate: Double(rate)
                )
            default: continue
            }
        }
        return info
    }

    static func longCodecName(_ fourCC: String) -> String {
        let map: [String: String] = [
            "avc1": "H.264 / AVC", "hvc1": "H.265 / HEVC", "hev1": "H.265 / HEVC",
            "dvh1": "Dolby Vision (HEVC)", "dvhe": "Dolby Vision (HEVC)",
            "apch": "Apple ProRes 422 HQ", "apcn": "Apple ProRes 422", "apcs": "Apple ProRes 422 LT",
            "apco": "Apple ProRes 422 Proxy", "ap4h": "Apple ProRes 4444", "ap4x": "Apple ProRes 4444 XQ",
            "vp09": "VP9", "av01": "AV1",
            "mp4a": "AAC", "ac-3": "AC-3", "ec-3": "E-AC-3 (Dolby Digital Plus)",
            "lpcm": "PCM", "alac": "Apple Lossless", "flac": "FLAC", "opus": "Opus"
        ]
        return map[fourCC.lowercased()] ?? fourCC
    }

    static func chromaFor(fourCC: String) -> String? {
        let k = fourCC.lowercased()
        if ["avc1","hvc1","hev1","dvh1","dvhe","vp09","av01","mp4v"].contains(k) { return "4:2:0" }
        if ["apch","apcn","apcs","apco","v210","2vuy","yuv2"].contains(k) { return "4:2:2" }
        if ["ap4h","ap4x"].contains(k) { return "4:4:4:4" }
        if ["r210","r10k","bgra","rgba","v410"].contains(k) { return "4:4:4" }
        return nil
    }

    static func containerLabel(ext: String) -> String {
        switch ext.lowercased() {
        case "mov","qt": return "QuickTime (MOV)"
        case "mp4","m4v","m4a": return "MPEG-4 (MP4)"
        case "mxf": return "MXF"; case "mkv": return "Matroska (MKV)"
        case "wav": return "WAVE"; case "aiff","aif": return "AIFF"
        case "mp3": return "MP3"; case "flac": return "FLAC"
        default: return ext.uppercased()
        }
    }

    static func fourCCString(_ x: FourCharCode) -> String {
        let bytes: [UInt8] = [UInt8((x >> 24) & 0xFF), UInt8((x >> 16) & 0xFF), UInt8((x >> 8) & 0xFF), UInt8(x & 0xFF)]
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "----"
    }
}

// MARK: - Conformity check (version CLI minimaliste)

struct CLIConformityResult: Codable {
    let ruleID: String
    let title: String
    let expected: String
    let actual: String
    let status: String     // pass | fail | warning | n/a
    let severity: String   // mandatory | recommended | informational
}

enum CLIConformity {
    static func check(_ info: CLIInfo, preset: String) -> [CLIConformityResult] {
        switch preset {
        case "broadcast.ebu.r128":
            return [
                check_("audio.sr", "Sample rate", "≥ 48 kHz", info.audio?.sampleRate ?? 0, ok: (info.audio?.sampleRate ?? 0) >= 48000, severity: "recommended"),
                check_("audio.codec", "Codec audio", "PCM ou AAC/AC-3", info.audio?.codecName ?? "—", ok: info.audio != nil, severity: "mandatory")
            ]
        case "netflix.4k.hdr10":
            return [
                check_("v.codec", "Codec vidéo", "HEVC", info.video?.codecName ?? "—",
                       ok: (info.video?.codecName ?? "").contains("HEVC"), severity: "mandatory"),
                check_("v.res", "Résolution", "3840×2160",
                       "\(info.video?.width ?? 0)×\(info.video?.height ?? 0)",
                       ok: info.video?.width == 3840 && info.video?.height == 2160, severity: "mandatory"),
                check_("v.bd", "Profondeur", "≥ 10 bits", "\(info.video?.bitDepth ?? 0) bits",
                       ok: (info.video?.bitDepth ?? 0) >= 10, severity: "mandatory"),
                check_("c.transfer", "Transfer", "PQ (ST 2084)", info.video?.transferFunction ?? "—",
                       ok: (info.video?.transferFunction ?? "").contains("2084"), severity: "mandatory")
            ]
        case "netflix.4k.sdr":
            return [
                check_("v.res", "Résolution", "3840×2160", "\(info.video?.width ?? 0)×\(info.video?.height ?? 0)",
                       ok: info.video?.width == 3840 && info.video?.height == 2160, severity: "mandatory"),
                check_("a.sr", "Sample rate", "≥ 48 kHz", "\(info.audio?.sampleRate ?? 0) Hz",
                       ok: (info.audio?.sampleRate ?? 0) >= 48000, severity: "mandatory")
            ]
        case "youtube.4k":
            return [
                check_("v.res", "Résolution", "≥ 3840×2160", "\(info.video?.width ?? 0)×\(info.video?.height ?? 0)",
                       ok: (info.video?.width ?? 0) >= 3840 && (info.video?.height ?? 0) >= 2160, severity: "recommended"),
                check_("a.sr", "Sample rate", "≥ 48 kHz", "\(info.audio?.sampleRate ?? 0) Hz",
                       ok: (info.audio?.sampleRate ?? 0) >= 48000, severity: "mandatory")
            ]
        case "prores.422hq":
            return [
                check_("v.codec", "Codec", "Apple ProRes 422 HQ", info.video?.codecName ?? "—",
                       ok: (info.video?.codecName ?? "").contains("ProRes"), severity: "mandatory"),
                check_("v.bd", "Profondeur", "≥ 10 bits", "\(info.video?.bitDepth ?? 0) bits",
                       ok: (info.video?.bitDepth ?? 0) >= 10, severity: "mandatory")
            ]
        case "web.html5":
            return [
                check_("v.codec", "Codec vidéo", "H.264", info.video?.codecName ?? "—",
                       ok: (info.video?.codecName ?? "").contains("H.264"), severity: "mandatory"),
                check_("a.codec", "Codec audio", "AAC", info.audio?.codecName ?? "—",
                       ok: (info.audio?.codecName ?? "").contains("AAC"), severity: "mandatory")
            ]
        case "dcp.feature":
            return [
                check_("v.codec", "Codec", "JPEG 2000", info.video?.codecName ?? "—",
                       ok: (info.video?.codecName ?? "").contains("JPEG"), severity: "mandatory")
            ]
        default:
            fputs("Preset inconnu : \(preset)\n", stderr)
            return []
        }
    }

    private static func check_(_ id: String, _ title: String, _ expected: String, _ actual: Any, ok: Bool, severity: String) -> CLIConformityResult {
        CLIConformityResult(
            ruleID: id, title: title, expected: expected,
            actual: "\(actual)", status: ok ? "pass" : "fail", severity: severity
        )
    }
}

// MARK: - Print

enum CLIPrinter {
    static func printSummary(_ info: CLIInfo) {
        let g = info.general
        print("📁 \(g.fileName)")
        print("   Conteneur : \(g.container)")
        print("   Taille    : \(format(bytes: g.fileSize))")
        print("   Durée     : \(format(duration: g.duration))")
        if let br = g.overallBitrate {
            print("   Débit     : \(format(bitsPerSec: Double(br)))")
        }
        if let v = info.video {
            print("\n🎬 Vidéo")
            print("   Codec     : \(v.codecName) (\(v.codecFourCC))")
            print("   Résolution: \(v.width)×\(v.height)")
            print("   FPS       : \(String(format: "%.3f", v.nominalFrameRate))")
            if let d = v.bitDepth { print("   Profondeur: \(d) bits/composante") }
            if let cs = v.chromaSubsampling { print("   Chroma    : \(cs)") }
            if let r = v.estimatedDataRate { print("   Débit V   : \(format(bitsPerSec: r))") }
            if let p = v.colorPrimaries { print("   Primaries : \(p)") }
            if let t = v.transferFunction { print("   Transfer  : \(t)") }
        }
        if let a = info.audio {
            print("\n🔊 Audio")
            print("   Codec     : \(a.codecName) (\(a.codecFourCC))")
            print("   Canaux    : \(a.channelCount)")
            print("   Fréquence : \(String(format: "%.1f kHz", a.sampleRate/1000))")
            if let bd = a.bitsPerChannel { print("   Bits      : \(bd)") }
            if let r = a.estimatedDataRate { print("   Débit A   : \(format(bitsPerSec: r))") }
        }
    }

    static func printConformity(presetID: String, results: [CLIConformityResult]) {
        print("\n✅ Conformité — \(presetID)")
        for r in results {
            let icon: String = {
                switch r.status {
                case "pass": return "✅"
                case "fail": return r.severity == "mandatory" ? "❌" : "⚠️ "
                default: return "—"
                }
            }()
            print("  \(icon) \(r.title) — attendu : \(r.expected) | actuel : \(r.actual)")
        }
    }

    static func format(bytes: Int64) -> String {
        let f = ByteCountFormatter(); f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
    static func format(duration: Double) -> String {
        let t = Int(duration); return String(format: "%02d:%02d:%02d", t/3600, (t%3600)/60, t%60)
    }
    static func format(bitsPerSec: Double) -> String {
        let kbps = bitsPerSec/1000
        if kbps >= 1000 { return String(format: "%.2f Mb/s", kbps/1000) }
        return String(format: "%.0f kb/s", kbps)
    }
}

extension JSONEncoder {
    static func misiinfo(pretty: Bool) -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return enc
    }
}
