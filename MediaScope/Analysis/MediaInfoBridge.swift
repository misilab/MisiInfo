import Foundation
import Darwin

/// Données extraites via MediaInfoLib. Optionnel : si la lib n'est pas présente,
/// MisiInfo continue de fonctionner avec les seules données AVFoundation.
nonisolated struct MediaInfoData: Sendable, Hashable {
    let format: String?
    let formatProfile: String?
    let codecID: String?
    let encodedLibrary: String?
    let writingApplication: String?
    let writingLibrary: String?
    let bitRateMode: String?      // CBR / VBR / VBR with avg
    let streamSize: String?       // taille du flux vidéo seul (string formatée par MI)
    let referenceFrames: String?
    let formatLevel: String?
    let chromaSubsampling: String?
    let scanType: String?
    let scanOrder: String?
    let compressionRatio: String?
    let extraVideo: [String: String]
    let extraAudio: [String: String]
    let extraGeneral: [String: String]
    let rawJSON: String?

    var isEmpty: Bool {
        format == nil && formatProfile == nil && codecID == nil &&
        encodedLibrary == nil && writingApplication == nil &&
        extraVideo.isEmpty && extraAudio.isEmpty && extraGeneral.isEmpty
    }
}

/// Pont vers `libmediainfo.0.dylib` chargé dynamiquement via `dlopen`.
/// L'app reste fonctionnelle si la bibliothèque n'est pas installée — tous les appels
/// retournent simplement `nil` et MisiInfo se rabat sur ses données AVFoundation.
///
/// Pour activer : suivre les instructions de `INSTALL_MEDIAINFO.md` à la racine du projet.
nonisolated enum MediaInfoBridge {

    // MARK: Chargement de la bibliothèque

    static let diagnostics: String = {
        var lines: [String] = []
        let paths = [
            "libmediainfo.0.dylib",
            "/usr/local/lib/libmediainfo.0.dylib",
            "/opt/homebrew/lib/libmediainfo.0.dylib",
            (Bundle.main.privateFrameworksPath ?? "") + "/libmediainfo.0.dylib"
        ]
        for path in paths {
            if let h = dlopen(path, RTLD_NOW) {
                lines.append("✅ Chargée depuis : \(path)")
                dlclose(h)  // évite la fuite de handle (libHandle gère le vrai chargement)
            } else {
                let err = dlerror().map { String(cString: $0) } ?? "(pas d'erreur)"
                lines.append("❌ \(path) → \(err)")
            }
        }
        return lines.joined(separator: "\n")
    }()

    private static let libHandle: UnsafeMutableRawPointer? = {
        let paths = [
            "libmediainfo.0.dylib",
            "/usr/local/lib/libmediainfo.0.dylib",
            "/opt/homebrew/lib/libmediainfo.0.dylib",
            (Bundle.main.privateFrameworksPath ?? "") + "/libmediainfo.0.dylib"
        ]
        for path in paths {
            if let h = dlopen(path, RTLD_NOW) { return h }
        }
        return nil
    }()

    static var isAvailable: Bool { libHandle != nil }

    // MARK: Signatures C (API ASCII : MediaInfoA_*)

    private typealias MIVoid = UnsafeMutableRawPointer
    private typealias MINew = @convention(c) () -> MIVoid?
    private typealias MIDelete = @convention(c) (MIVoid?) -> Void
    private typealias MIOpen = @convention(c) (MIVoid?, UnsafePointer<CChar>) -> Int
    private typealias MIClose = @convention(c) (MIVoid?) -> Void
    private typealias MIOption = @convention(c) (MIVoid?, UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafePointer<CChar>?
    private typealias MIInform = @convention(c) (MIVoid?, Int) -> UnsafePointer<CChar>?

    // MARK: API publique

    static func analyze(url: URL) -> MediaInfoData? {
        guard let lib = libHandle else { return nil }

        guard
            let newPtr = dlsym(lib, "MediaInfoA_New"),
            let delPtr = dlsym(lib, "MediaInfoA_Delete"),
            let openPtr = dlsym(lib, "MediaInfoA_Open"),
            let closePtr = dlsym(lib, "MediaInfoA_Close"),
            let optionPtr = dlsym(lib, "MediaInfoA_Option"),
            let informPtr = dlsym(lib, "MediaInfoA_Inform")
        else { return nil }

        let new = unsafeBitCast(newPtr, to: MINew.self)
        let del = unsafeBitCast(delPtr, to: MIDelete.self)
        let open = unsafeBitCast(openPtr, to: MIOpen.self)
        let close = unsafeBitCast(closePtr, to: MIClose.self)
        let option = unsafeBitCast(optionPtr, to: MIOption.self)
        let inform = unsafeBitCast(informPtr, to: MIInform.self)

        guard let handle = new() else { return nil }
        defer {
            close(handle)
            del(handle)
        }

        // MediaInfoLib retourne > 0 si le fichier est ouvert correctement, 0 sinon.
        let openResult = url.path.withCString { open(handle, $0) }
        guard openResult > 0 else { return nil }

        _ = "Output".withCString { k in
            "JSON".withCString { v in
                option(handle, k, v)
            }
        }
        guard let cstr = inform(handle, 0) else { return nil }
        let json = String(cString: cstr)
        return parseJSON(json)
    }

    // MARK: Parsing JSON MediaInfo

    private static func parseJSON(_ json: String) -> MediaInfoData? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let media = obj["media"] as? [String: Any]
        else { return nil }

        let tracksRaw = media["track"]
        let tracks: [[String: Any]]
        if let arr = tracksRaw as? [[String: Any]] {
            tracks = arr
        } else if let single = tracksRaw as? [String: Any] {
            tracks = [single]
        } else {
            tracks = []
        }

        let general = tracks.first { ($0["@type"] as? String) == "General" }
        let video = tracks.first { ($0["@type"] as? String) == "Video" }
        let audio = tracks.first { ($0["@type"] as? String) == "Audio" }

        return MediaInfoData(
            format: g(general, "Format"),
            formatProfile: g(video, "Format_Profile") ?? g(audio, "Format_Profile"),
            codecID: g(video, "CodecID") ?? g(audio, "CodecID"),
            encodedLibrary: g(video, "Encoded_Library") ?? g(audio, "Encoded_Library"),
            writingApplication: g(general, "Encoded_Application"),
            writingLibrary: g(general, "Encoded_Library"),
            bitRateMode: g(video, "BitRate_Mode") ?? g(audio, "BitRate_Mode"),
            streamSize: g(video, "StreamSize") ?? g(audio, "StreamSize"),
            referenceFrames: g(video, "Format_Settings_RefFrames"),
            formatLevel: g(video, "Format_Level"),
            chromaSubsampling: g(video, "ChromaSubsampling"),
            scanType: g(video, "ScanType"),
            scanOrder: g(video, "ScanOrder"),
            compressionRatio: g(video, "Compression_Ratio"),
            extraVideo: extractAll(video),
            extraAudio: extractAll(audio),
            extraGeneral: extractAll(general),
            rawJSON: json
        )
    }

    private static func g(_ dict: [String: Any]?, _ key: String) -> String? {
        guard let s = (dict?[key] as? String)?.trimmingCharacters(in: .whitespaces),
              !s.isEmpty else { return nil }
        return s
    }

    private static func extractAll(_ dict: [String: Any]?) -> [String: String] {
        guard let d = dict else { return [:] }
        var result: [String: String] = [:]
        for (k, v) in d {
            if k.hasPrefix("@") { continue }
            if let s = v as? String, !s.isEmpty { result[k] = s }
        }
        return result
    }
}
