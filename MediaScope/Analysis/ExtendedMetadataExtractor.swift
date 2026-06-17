import Foundation
import AVFoundation
import CoreServices

/// Extracteur de métadonnées étendues : GPS, EXIF caméra, dates moov, accessibilité,
/// chapitres, tags Finder, commentaires Spotlight, xattr.
nonisolated enum ExtendedMetadataExtractor {

    // MARK: - GPS / Location

    /// Cherche un AVMetadataItem de type location (iPhone, drones, GoPro).
    /// Retourne (lat, lon, alt) parsé du format ISO 6709 "+37.4220-122.0840+0.0/".
    static func extractGPS(from items: [AVMetadataItem]) async -> GPSLocation? {
        for item in items {
            let id = item.identifier?.rawValue ?? ""
            let key = (item.key as? String) ?? ""
            let common = item.commonKey?.rawValue ?? ""
            let matchesLocation = id.contains("location") || id.contains("ISO6709")
                || key.lowercased().contains("location") || common == "location"
            guard matchesLocation else { continue }
            if let raw = (try? await item.load(.stringValue)) ?? nil,
               let parsed = parseISO6709(raw) {
                return parsed
            }
        }
        return nil
    }

    /// Parse ISO 6709 : `+37.4220-122.0840+0.0/` ou `+37.4220-122.0840+0.0CRSWGS_84/`.
    /// Pattern : signe + latitude, signe + longitude, [signe + altitude], [suffixe CRS], '/'.
    static func parseISO6709(_ s: String) -> GPSLocation? {
        var str = s
        if str.hasSuffix("/") { str.removeLast() }
        // Coupe le suffixe CRS éventuel (ex : "CRSWGS_84")
        if let crsRange = str.range(of: "CRS", options: [.caseInsensitive]) {
            str = String(str[..<crsRange.lowerBound])
        }
        let pattern = #"([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)([+-]\d+(?:\.\d+)?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(str.startIndex..., in: str)
        guard let m = regex.firstMatch(in: str, range: range) else { return nil }
        guard let latR = Range(m.range(at: 1), in: str),
              let lonR = Range(m.range(at: 2), in: str),
              let lat = Double(str[latR]),
              let lon = Double(str[lonR]) else { return nil }
        var alt: Double? = nil
        if let altR = Range(m.range(at: 3), in: str) {
            alt = Double(str[altR])
        }
        return GPSLocation(latitude: lat, longitude: lon, altitude: alt)
    }

    // MARK: - Caméra (EXIF QuickTime)

    static func extractCameraInfo(from items: [AVMetadataItem]) async -> CameraInfo {
        var make: String?
        var model: String?
        var software: String?
        var recordingDate: Date?
        var lensModel: String?
        var liveVideo: Bool? = nil

        func sval(_ item: AVMetadataItem) async -> String? {
            (try? await item.load(.stringValue)) ?? nil
        }
        func dval(_ item: AVMetadataItem) async -> Date? {
            (try? await item.load(.dateValue)) ?? nil
        }

        for item in items {
            let id = (item.identifier?.rawValue ?? "").lowercased()
            let key = ((item.key as? String) ?? "").lowercased()
            let any = id + "|" + key
            if make == nil, any.hasSuffix(".make") || any.contains("|make") || id == "com.apple.quicktime.make" {
                make = await sval(item)
            }
            if model == nil, any.hasSuffix(".model") || any.contains("|model") || id == "com.apple.quicktime.model" {
                model = await sval(item)
            }
            if software == nil, any.hasSuffix(".software") || any.contains("|software") || id == "com.apple.quicktime.software" {
                software = await sval(item)
            }
            if recordingDate == nil, any.contains("creationdate") || any.contains("creation_time") {
                if let d = await dval(item) {
                    recordingDate = d
                } else if let s = await sval(item) {
                    let f = ISO8601DateFormatter()
                    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
                    if let d = f.date(from: s) {
                        recordingDate = d
                    } else {
                        f.formatOptions = [.withInternetDateTime]
                        if let d = f.date(from: s) { recordingDate = d }
                    }
                }
            }
            if lensModel == nil, any.contains("lens") {
                lensModel = await sval(item)
            }
            if any.contains("live-photo") || any.contains("livephoto") {
                liveVideo = true
            }
        }
        return CameraInfo(
            make: make,
            model: model,
            software: software,
            lensModel: lensModel,
            recordingDate: recordingDate,
            isLivePhoto: liveVideo
        )
    }

    // MARK: - Chapitres

    static func extractChapters(asset: AVAsset) async -> [ChapterMarker] {
        let locales = (try? await asset.load(.availableChapterLocales)) ?? []
        let preferred = locales.first { $0.identifier == Locale.current.identifier }
            ?? locales.first
            ?? Locale(identifier: "en_US")
        let groups = (try? await asset.loadChapterMetadataGroups(withTitleLocale: preferred)) ?? []
        var markers: [ChapterMarker] = []
        for group in groups {
            let timeRange = group.timeRange
            var title: String?
            for item in group.items {
                let cKey = item.commonKey?.rawValue ?? ""
                if cKey == "title" {
                    title = (try? await item.load(.stringValue)) ?? nil
                    break
                }
            }
            let startSec = CMTimeGetSeconds(timeRange.start)
            guard startSec.isFinite else { continue }
            markers.append(ChapterMarker(startTime: startSec, title: title ?? ""))
        }
        return markers
    }

    // MARK: - Caractéristiques d'accessibilité / contenu

    static func extractMediaCharacteristics(asset: AVAsset) async -> Set<String> {
        let all = (try? await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)) ?? []
        return Set(all.map { $0.rawValue })
    }

    // MARK: - Finder / Spotlight / xattr (système macOS)

    static func extractFinderTags(url: URL) -> [String] {
        guard let values = try? url.resourceValues(forKeys: [.tagNamesKey]),
              let tags = values.tagNames else { return [] }
        return tags
    }

    static func extractSpotlightComment(url: URL) -> String? {
        guard let mdItem = MDItemCreateWithURL(nil, url as CFURL) else { return nil }
        let str = MDItemCopyAttribute(mdItem, kMDItemFinderComment) as? String
        return (str?.isEmpty == false) ? str : nil
    }

    /// Lit l'extended attribute `com.apple.metadata:kMDItemWhereFroms` qui contient
    /// l'URL/source de téléchargement (plist binaire avec liste de strings).
    /// Retourne url ← referrer si disponibles.
    static func extractDownloadSource(url: URL) -> String? {
        let attr = "com.apple.metadata:kMDItemWhereFroms"
        let size = getxattr(url.path, attr, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        // Alloue un peu plus pour absorber une race condition (l'attribut grandit entre les
        // deux appels). On utilise ensuite la taille effectivement lue.
        let buf = max(size, size + 64)
        var data = Data(count: buf)
        let read = data.withUnsafeMutableBytes { ptr -> Int in
            getxattr(url.path, attr, ptr.baseAddress, buf, 0, 0)
        }
        guard read > 0 else { return nil }
        data = data.prefix(read)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return nil }
        if let arr = plist as? [String], !arr.isEmpty {
            return arr.prefix(2).joined(separator: " ← ")
        }
        return nil
    }

    // MARK: - Helpers

    /// Détermine un nom de pixel format détaillé style FFmpeg.
    static func detailedPixelFormat(fourCC: String, bitDepth: Int?, chromaSubsampling: String?) -> String? {
        let cc = fourCC.lowercased()
        let cs = chromaSubsampling ?? ""
        switch cc {
        case "avc1":
            switch (cs, bitDepth ?? 8) {
            case ("4:2:0", 8): return "yuv420p"
            case ("4:2:0", 10): return "yuv420p10le"
            case ("4:2:2", 8): return "yuv422p"
            case ("4:2:2", 10): return "yuv422p10le"
            case ("4:4:4", 8): return "yuv444p"
            case ("4:4:4", 10): return "yuv444p10le"
            default: return nil
            }
        case "hvc1", "hev1", "dvh1", "dvhe":
            switch (cs, bitDepth ?? 8) {
            case ("4:2:0", 8): return "yuv420p"
            case ("4:2:0", 10): return "p010"  // (semi-planar HEVC 10-bit)
            case ("4:2:2", 10): return "p210"
            case ("4:4:4", 10): return "yuv444p10le"
            default: return nil
            }
        case "apch", "apcn", "apcs", "apco": return "yuv422p10le"
        case "ap4h": return "yuva444p10le"
        case "ap4x": return "yuva444p12le"
        case "v210": return "uyvy422_10"
        case "v410": return "yuv444p10le"
        case "2vuy", "yuv2", "yuvs": return "uyvy422"
        case "bgra": return "bgra"
        case "rgba": return "rgba"
        case "r210": return "rgb30be"
        case "r10k": return "rgb30le"
        default: return nil
        }
    }

    /// Profil Dolby Vision lu depuis l'atom `dvcC` (configurationVersion / profile / level).
    /// Référence : Dolby Vision Streams within the ISO Base Media File Format spec, §2.2.
    static func dolbyVisionProfile(extensionAtoms atoms: [String: Any]?) -> String? {
        guard let atoms else { return nil }
        let data = (atoms["dvcC"] as? Data) ?? (atoms["dvvC"] as? Data)
        guard let d = data, d.count >= 4 else { return nil }
        let bytes = [UInt8](d)
        // bytes[0..1] : versions / NAL-type, bytes[2] : MSB7=profile (7 bits), bit0=level MSB
        let profile = (bytes[2] >> 1) & 0x7F
        let level = ((bytes[2] & 0x01) << 5) | (bytes[3] >> 3)
        let name: String
        switch profile {
        case 4: name = "Dolby Vision Profile 4 (BL HDR + EL SDR)"
        case 5: name = "Dolby Vision Profile 5 (IPT-PQ-c2, sans rétrocompat)"
        case 7: name = "Dolby Vision Profile 7 (BL HDR10 + EL + RPU)"
        case 8: name = "Dolby Vision Profile 8 (HDR10/HLG compatible, BL+RPU)"
        case 9: name = "Dolby Vision Profile 9 (AVC HDR10 compatible)"
        case 10: name = "Dolby Vision Profile 10 (AV1)"
        default: name = "Dolby Vision Profile \(profile)"
        }
        return "\(name) @L\(level)"
    }
}

// MARK: - Modèles

nonisolated struct GPSLocation: Hashable, Sendable, Codable {
    let latitude: Double
    let longitude: Double
    let altitude: Double?

    var formatted: String {
        let latStr = String(format: "%.5f°", latitude) + (latitude >= 0 ? " N" : " S")
        let lonStr = String(format: "%.5f°", longitude) + (longitude >= 0 ? " E" : " W")
        if let altitude {
            return "\(latStr), \(lonStr), \(String(format: "%.1f m", altitude))"
        }
        return "\(latStr), \(lonStr)"
    }

    /// URL Apple Plans / Apple Maps avec un pin sur le lieu.
    var mapsURL: URL? {
        URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=Position")
    }
}

nonisolated struct CameraInfo: Hashable, Sendable {
    let make: String?
    let model: String?
    let software: String?
    let lensModel: String?
    let recordingDate: Date?
    let isLivePhoto: Bool?

    var hasAny: Bool {
        make != nil || model != nil || software != nil || lensModel != nil || recordingDate != nil
    }
}

nonisolated struct ChapterMarker: Hashable, Sendable, Identifiable {
    let id = UUID()
    let startTime: TimeInterval
    let title: String

    var startFormatted: String {
        guard startTime.isFinite, startTime >= 0 else { return "—" }
        let total = Int(startTime)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let ms = max(0, Int((startTime - Double(total)) * 1000))
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
