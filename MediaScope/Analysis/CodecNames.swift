import Foundation
import CoreMedia

nonisolated enum CodecNames {

    static func name(for fourCC: String, mediaType: String) -> String {
        let key = fourCC.lowercased()
        if mediaType == "video", let n = videoMap[key] { return n }
        if mediaType == "audio", let n = audioMap[key] { return n }
        return fourCC
    }

    /// Nom long technique du codec (ex : "Advanced Video Coding", "High Efficiency Video Coding").
    static func longName(for fourCC: String) -> String? {
        let k = fourCC.lowercased()
        switch k {
        case "avc1": return "Advanced Video Coding"
        case "hvc1", "hev1": return "High Efficiency Video Coding"
        case "dvh1", "dvhe": return "Dolby Vision (HEVC base layer)"
        case "vp08": return "VP8 Video"
        case "vp09": return "VP9 Video"
        case "av01": return "AV1 Video"
        case "apch": return "Apple ProRes 422 HQ"
        case "apcn": return "Apple ProRes 422 Standard"
        case "apcs": return "Apple ProRes 422 LT"
        case "apco": return "Apple ProRes 422 Proxy"
        case "ap4h": return "Apple ProRes 4444 (12-bit)"
        case "ap4x": return "Apple ProRes 4444 XQ"
        case "mp4v": return "MPEG-4 Visual"
        case "mp2v": return "MPEG-2 Video"
        case "mp4a": return "Advanced Audio Coding (MPEG-4)"
        case "ac-3": return "Dolby Digital (ATSC A/52)"
        case "ec-3": return "Dolby Digital Plus (ATSC A/52B)"
        case "alac": return "Apple Lossless Audio Codec"
        case ".mp3", "mp3 ": return "MPEG-1 Audio Layer III"
        case "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64": return "Linear PCM (non compressé)"
        case "opus": return "Opus Audio"
        case "flac": return "Free Lossless Audio Codec"
        default: return nil
        }
    }

    /// Espace de couleurs typique (YUV / RGB / RGBA / Bayer RAW).
    static func colorSpace(forVideoFourCC fourCC: String) -> String? {
        let k = fourCC.lowercased()
        switch k {
        case "rgba", "bgra": return "RGBA"
        case "raw ", "r210", "r10k": return "RGB"
        case "ap4h", "ap4x": return "YUVA"  // 4:4:4:4 = YUV + alpha
        case "avc1", "hvc1", "hev1", "dvh1", "dvhe",
             "vp08", "vp09", "av01",
             "apch", "apcn", "apcs", "apco",
             "v210", "v410", "2vuy", "yuv2", "yuvs",
             "mp4v", "mp2v", "dvcp", "dvpp", "dv5p", "dv5n":
            return "YUV"
        case "jpeg", "mjpa", "mjpb": return "YUV"
        default: return nil
        }
    }

    /// Mode de compression (clé de traduction).
    static func compressionMode(forFourCC fourCC: String, mediaType: String) -> String? {
        let k = fourCC.lowercased()
        // Sans perte
        let lossless: Set<String> = ["apch", "apcn", "apcs", "apco", "ap4h", "ap4x", "alac", "flac"]
        if lossless.contains(k) { return "Sans perte" }
        // Non compressé
        let uncompressed: Set<String> = [
            "raw ", "2vuy", "yuv2", "yuvs", "v210", "v410", "r210", "r10k", "bgra", "rgba",
            "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64"
        ]
        if uncompressed.contains(k) { return "Non compressé" }
        return "Avec perte"
    }

    /// Échantillons par frame audio selon codec/profil.
    static func samplesPerFrame(forAudioFourCC fourCC: String, audioProfile: String?) -> Int? {
        let k = fourCC.lowercased()
        switch k {
        case "mp4a":
            if let p = audioProfile {
                if p.contains("HE-AAC v2") { return 2048 }
                if p.contains("HE-AAC") { return 2048 }
                if p.contains("AAC LD") { return 512 }
            }
            return 1024  // AAC LC par défaut
        case ".mp3", "mp3 ": return 1152
        case "ac-3", "ec-3": return 1536
        case "alac": return 4096
        case "flac": return nil  // variable
        case "opus": return nil  // variable (typique 960)
        case "lpcm", "sowt", "twos", "in24", "in32", "fl32", "fl64": return 1
        default: return nil
        }
    }

    /// Identifiant codec détaillé style MediaInfo (`mp4a-40-2` pour AAC LC).
    static func codecIDLong(forAudioFourCC fourCC: String, audioProfile: String?) -> String? {
        if fourCC.lowercased() == "mp4a" {
            guard let profile = audioProfile else { return "mp4a" }
            // Object type ID (MPEG-4 audio)
            if profile.contains("HE-AAC v2") { return "mp4a-40-29" }
            if profile.contains("HE-AAC") { return "mp4a-40-5" }
            if profile.contains("AAC Main") { return "mp4a-40-1" }
            if profile.contains("AAC LC") { return "mp4a-40-2" }
            if profile.contains("AAC SSR") { return "mp4a-40-3" }
            if profile.contains("AAC LTP") { return "mp4a-40-4" }
            if profile.contains("AAC LD") { return "mp4a-40-23" }
            return "mp4a"
        }
        return fourCC
    }

    static func chromaSubsampling(forVideoFourCC fourCC: String) -> String? {
        switch fourCC.lowercased() {
        case "apch", "apcn", "apcs", "apco": return "4:2:2"
        case "ap4h", "ap4x": return "4:4:4:4"
        case "v210", "2vuy", "yuv2", "yuvs": return "4:2:2"
        case "v410": return "4:4:4"
        case "r210", "r10k", "bgra", "rgba", "rgb ": return "4:4:4"
        case "avc1", "hvc1", "hev1", "dvh1", "dvhe", "vp09", "av01", "mp4v", "vp80", "vp90":
            return "4:2:0"
        default: return nil
        }
    }

    static func bitDepth(forVideoFourCC fourCC: String) -> Int? {
        switch fourCC.lowercased() {
        case "v210", "r210", "v410", "r10k", "ap4x": return 10
        case "apch", "apcn", "apcs", "apco", "ap4h": return 10
        case "2vuy", "yuv2", "yuvs", "bgra", "rgba": return 8
        case "avc1", "mp4v": return 8
        case "hvc1", "hev1": return nil
        default: return nil
        }
    }

    private static let videoMap: [String: String] = [
        "avc1": "H.264 / AVC",
        "hvc1": "H.265 / HEVC",
        "hev1": "H.265 / HEVC",
        "dvh1": "Dolby Vision (HEVC)",
        "dvhe": "Dolby Vision (HEVC)",
        "apch": "Apple ProRes 422 HQ",
        "apcn": "Apple ProRes 422",
        "apcs": "Apple ProRes 422 LT",
        "apco": "Apple ProRes 422 Proxy",
        "ap4h": "Apple ProRes 4444",
        "ap4x": "Apple ProRes 4444 XQ",
        "aprn": "Apple ProRes RAW",
        "aprh": "Apple ProRes RAW HQ",
        "icod": "Apple Intermediate",
        "jpeg": "Motion JPEG",
        "mjpa": "Motion JPEG A",
        "mjpb": "Motion JPEG B",
        "mp4v": "MPEG-4 Visual",
        "mp2v": "MPEG-2 Video",
        "vp08": "VP8",
        "vp09": "VP9",
        "av01": "AV1",
        "dvc ": "DV",
        "dvcp": "DV PAL",
        "dvpp": "DVCPRO PAL",
        "dv5p": "DVCPRO50 PAL",
        "dv5n": "DVCPRO50 NTSC",
        "dvhp": "DVCPRO HD",
        "dvhq": "DVCPRO HD",
        "raw ": "Uncompressed RGB",
        "2vuy": "Uncompressed YUV 4:2:2 8-bit",
        "yuv2": "Uncompressed YUV 4:2:2 8-bit",
        "yuvs": "Uncompressed YUV 4:2:2 8-bit",
        "v210": "Uncompressed YUV 4:2:2 10-bit",
        "v410": "Uncompressed YUV 4:4:4 10-bit",
        "r210": "Uncompressed RGB 10-bit",
        "r10k": "Uncompressed RGB 10-bit",
        "bgra": "Uncompressed BGRA",
        "rgba": "Uncompressed RGBA",
        "tx3g": "3GPP Timed Text",
        "c608": "CEA-608 Caption",
        "c708": "CEA-708 Caption"
    ]

    private static let audioMap: [String: String] = [
        "mp4a": "AAC",
        "lpcm": "PCM (Linear)",
        "sowt": "PCM signed 16-bit LE",
        "twos": "PCM signed 16-bit BE",
        "in24": "PCM signed 24-bit",
        "in32": "PCM signed 32-bit",
        "fl32": "PCM Float 32-bit",
        "fl64": "PCM Float 64-bit",
        "ac-3": "AC-3 (Dolby Digital)",
        "ec-3": "E-AC-3 (Dolby Digital Plus)",
        "alac": "Apple Lossless (ALAC)",
        ".mp3": "MP3",
        "mp3 ": "MP3",
        "opus": "Opus",
        "vorb": "Vorbis",
        "flac": "FLAC",
        "ima4": "IMA 4:1",
        "ulaw": "µ-Law 2:1",
        "alaw": "A-Law 2:1",
        "qdm2": "QDesign Music 2",
        "samr": "AMR Narrowband"
    ]
}

nonisolated enum ColorMetadataNames {
    static func primariesLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case String(kCMFormatDescriptionColorPrimaries_ITU_R_709_2): return "ITU-R BT.709"
        case String(kCMFormatDescriptionColorPrimaries_EBU_3213): return "EBU 3213 (PAL)"
        case String(kCMFormatDescriptionColorPrimaries_SMPTE_C): return "SMPTE-C (NTSC)"
        case String(kCMFormatDescriptionColorPrimaries_DCI_P3): return "DCI-P3"
        case String(kCMFormatDescriptionColorPrimaries_P3_D65): return "Display P3 (D65)"
        case String(kCMFormatDescriptionColorPrimaries_ITU_R_2020): return "ITU-R BT.2020"
        case String(kCMFormatDescriptionColorPrimaries_P22): return "EBU 3213-E (P22)"
        default: return raw
        }
    }

    static func transferLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case String(kCMFormatDescriptionTransferFunction_ITU_R_709_2): return "ITU-R BT.709"
        case String(kCMFormatDescriptionTransferFunction_SMPTE_240M_1995): return "SMPTE 240M"
        case String(kCMFormatDescriptionTransferFunction_UseGamma): return "Gamma"
        case String(kCMFormatDescriptionTransferFunction_ITU_R_2020): return "ITU-R BT.2020"
        case String(kCMFormatDescriptionTransferFunction_SMPTE_ST_428_1): return "SMPTE ST 428-1"
        case String(kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ): return "SMPTE ST 2084 (PQ / HDR10)"
        case String(kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG): return "ITU-R BT.2100 (HLG)"
        case String(kCMFormatDescriptionTransferFunction_Linear): return "Linear"
        case String(kCMFormatDescriptionTransferFunction_sRGB): return "sRGB"
        default: return raw
        }
    }

    static func matrixLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw {
        case String(kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2): return "ITU-R BT.709"
        case String(kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4): return "ITU-R BT.601"
        case String(kCMFormatDescriptionYCbCrMatrix_SMPTE_240M_1995): return "SMPTE 240M"
        case String(kCMFormatDescriptionYCbCrMatrix_ITU_R_2020): return "ITU-R BT.2020"
        default: return raw
        }
    }

    static func isHDR(transferRaw: String?) -> Bool {
        guard let raw = transferRaw else { return false }
        if raw == String(kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ) { return true }
        if raw == String(kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG) { return true }
        return false
    }

    static func hdrFormat(transferRaw: String?, codecFourCC: String) -> String? {
        let cc = codecFourCC.lowercased()
        if cc == "dvh1" || cc == "dvhe" { return "Dolby Vision" }
        guard let raw = transferRaw else { return nil }
        if raw == String(kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ) { return "HDR10 (PQ)" }
        if raw == String(kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG) { return "HLG" }
        return nil
    }
}
