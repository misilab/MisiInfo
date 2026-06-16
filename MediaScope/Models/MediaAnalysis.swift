import Foundation

nonisolated struct MediaAnalysis: Identifiable, Hashable, Sendable {
    let id = UUID()
    let general: GeneralInfo
    let videoTracks: [VideoTrack]
    let audioTracks: [AudioTrack]
    let subtitleTracks: [SubtitleTrack]
    let timecode: TimecodeInfo?
    let metadata: [MetadataItem]
    let mediaInfo: MediaInfoData?
}

nonisolated struct GeneralInfo: Hashable, Sendable {
    let fileURL: URL
    let fileName: String
    let fileSize: Int64
    let containerFormat: String
    let containerExtension: String
    let utiType: String?
    let duration: Double
    let creationDate: Date?
    let modificationDate: Date?
    let overallBitrate: Int64?
    let encoder: String?
    let writingApplication: String?
    let hasAlphaChannel: Bool
    let hasHDRVideo: Bool
    let majorBrand: String?
    let compatibleBrands: [String]

    var durationFormatted: String {
        guard duration.isFinite, duration >= 0 else { return "—" }
        let total = Int(duration.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        let ms = Int((duration - Double(total)) * 1000)
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var overallBitrateFormatted: String? {
        guard let rate = overallBitrate, rate > 0 else { return nil }
        return Formatters.bitrate(Double(rate))
    }
}

nonisolated struct VideoTrack: Identifiable, Hashable, Sendable {
    let id = UUID()
    let trackID: Int32
    let codecFourCC: String
    let codecName: String
    let codecProfile: String?
    let width: Int
    let height: Int
    let displayWidth: Int
    let displayHeight: Int
    let pixelAspectRatio: Double?
    let nominalFrameRate: Float
    let minFrameDuration: Double?
    let estimatedDataRate: Float
    let totalFrames: Int?
    let bitDepth: Int?
    let colorPrimaries: String?
    let transferFunction: String?
    let yCbCrMatrix: String?
    let colorRange: String?
    let chromaSubsampling: String?
    let pixelFormat: String?
    let fieldOrder: String?
    let isHDR: Bool
    let hdrFormat: String?
    let maxCLL: Int?
    let maxFALL: Int?
    let hasMasteringDisplay: Bool
    let averageFrameSize: Int64?
    let trackMetadata: [MetadataItem]
    let colorSpace: String?
    let compressionMode: String?
    let bitsPerPixelFrame: Double?
    let frameRateMode: String?
    let codecLongName: String?
    let trackDuration: Double?
    /// Vignette PNG du premier frame (max 320px côté long).
    let posterFrame: Data?

    var resolutionLabel: String { "\(width) × \(height)" }
    var displayResolutionLabel: String { "\(displayWidth) × \(displayHeight)" }
    var aspectRatioLabel: String {
        guard displayHeight > 0 else { return "—" }
        let r = Double(displayWidth) / Double(displayHeight)
        return String(format: "%.3f:1", r)
    }
    var frameRateLabel: String {
        guard nominalFrameRate > 0 else { return "—" }
        return String(format: "%.3f fps", nominalFrameRate)
    }
    var bitrateLabel: String? {
        guard estimatedDataRate > 0 else { return nil }
        return Formatters.bitrate(Double(estimatedDataRate))
    }
}

nonisolated struct AudioTrack: Identifiable, Hashable, Sendable {
    let id = UUID()
    let trackID: Int32
    let codecFourCC: String
    let codecName: String
    let channelCount: Int
    let channelLayout: String?
    let channelMap: String?
    let sampleRate: Double
    let bitsPerChannel: Int?
    let estimatedDataRate: Float
    let isCompressed: Bool
    let endianness: String?
    let language: String?
    let audioProfile: String?
    let trackMetadata: [MetadataItem]
    let samplesPerFrame: Int?
    let totalSamples: Int64?
    let codecIDLong: String?
    let trackDuration: Double?
    /// Crêtes normalisées (0..1) pour visualisation waveform. ~600 valeurs typiques.
    let waveformPeaks: [Float]?
    /// Loudness intégré en LUFS (approximation K-weighted BS.1770). nil si non mesuré.
    let integratedLUFS: Double?
    /// Crête vraie en dBTP (true peak approximé via samples).
    let truePeakDBTP: Double?

    var sampleRateLabel: String {
        guard sampleRate > 0 else { return "—" }
        return String(format: "%.1f kHz", sampleRate / 1000)
    }
    var bitrateLabel: String? {
        guard estimatedDataRate > 0 else { return nil }
        return Formatters.bitrate(Double(estimatedDataRate))
    }
    /// Format simple "N (Layout)" — la View applique `LocalizedStringKey` pour traduire Mono/Stereo.
    var channelsLabel: String {
        if let layout = channelLayout, !layout.isEmpty { return "\(channelCount) (\(layout))" }
        return "\(channelCount)"
    }
}

nonisolated struct SubtitleTrack: Identifiable, Hashable, Sendable {
    let id = UUID()
    let trackID: Int32
    let format: String
    let language: String?
    let isClosedCaption: Bool
}

nonisolated struct TimecodeInfo: Hashable, Sendable {
    let startTimecode: String?
    let endTimecode: String?
    let frameRate: Float
    let dropFrame: Bool
    let trackID: Int32
}

nonisolated struct MetadataItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let key: String
    let value: String
    let keySpace: String?
}

nonisolated enum Formatters {
    static func bitrate(_ bitsPerSecond: Double) -> String {
        let kbps = bitsPerSecond / 1000
        if kbps >= 1000 {
            return String(format: "%.2f Mb/s", kbps / 1000)
        } else {
            return String(format: "%.0f kb/s", kbps)
        }
    }
}
