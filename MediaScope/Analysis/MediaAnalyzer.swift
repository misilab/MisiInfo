import Foundation
import AVFoundation
import CoreMedia
import CoreAudioTypes
import OSLog

nonisolated let mediaLog = Logger(subsystem: "fr.misilab.MediaScope", category: "analyzer")

nonisolated enum MediaAnalysisError: Error, LocalizedError {
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let reason): return reason
        }
    }
}

nonisolated enum MediaAnalyzer {

    static func analyze(url: URL) async throws -> MediaAnalysis {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: url)

        let duration: CMTime
        let allTracks: [AVAssetTrack]
        let rawMetadata: [AVMetadataItem]
        let commonMetadata: [AVMetadataItem]
        do {
            duration = try await asset.load(.duration)
            allTracks = try await asset.load(.tracks)
            rawMetadata = (try? await asset.load(.metadata)) ?? []
            commonMetadata = (try? await asset.load(.commonMetadata)) ?? []
        } catch {
            mediaLog.error("analyze load failed: \(error.localizedDescription, privacy: .public)")
            throw MediaAnalysisError.unreadable(error.localizedDescription)
        }

        let general = try await generalInfo(
            url: url,
            asset: asset,
            duration: duration,
            commonMetadata: commonMetadata,
            rawMetadata: rawMetadata
        )

        var videoTracks: [VideoTrack] = []
        var audioTracks: [AudioTrack] = []
        var subtitleTracks: [SubtitleTrack] = []
        var timecode: TimecodeInfo?

        for track in allTracks {
            switch track.mediaType {
            case .video:
                if let v = try? await analyzeVideo(track: track) { videoTracks.append(v) }
            case .audio:
                if let a = try? await analyzeAudio(track: track) { audioTracks.append(a) }
            case .subtitle, .closedCaption, .text:
                if let s = try? await analyzeSubtitle(track: track) { subtitleTracks.append(s) }
            case .timecode where timecode == nil:
                timecode = try? await analyzeTimecode(track: track, asset: asset)
            default:
                continue
            }
        }

        let meta = await collectMetadata(common: commonMetadata, all: rawMetadata)

        // Phase 2 : MediaInfoLib si disponible (graceful fallback)
        let miData = MediaInfoBridge.analyze(url: url)

        return MediaAnalysis(
            general: general,
            videoTracks: videoTracks,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            timecode: timecode,
            metadata: meta,
            mediaInfo: miData
        )
    }

    // MARK: General

    private static func generalInfo(
        url: URL,
        asset: AVURLAsset,
        duration: CMTime,
        commonMetadata: [AVMetadataItem],
        rawMetadata: [AVMetadataItem]
    ) async throws -> GeneralInfo {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentTypeKey
        ])
        let size = Int64(values.fileSize ?? 0)
        let durationSec = CMTimeGetSeconds(duration)
        let bitrate: Int64?
        if durationSec > 0, size > 0 {
            bitrate = Int64(Double(size) * 8 / durationSec)
        } else {
            bitrate = nil
        }

        let encoder = await findMetadataValue(in: commonMetadata + rawMetadata, matching: [
            "software", "encoder", "com.apple.quicktime.software",
            "com.apple.proapps.tools", "Writing application", "writingApp", "encoded_by"
        ])
        let writingApp = await findMetadataValue(in: commonMetadata + rawMetadata, matching: [
            "make", "model", "com.apple.quicktime.make", "com.apple.quicktime.model",
            "com.apple.proapps.serialnum", "WritingLibrary"
        ])

        // Asset characteristics
        var hasAlpha = false
        var hasHDR = false
        do {
            let characteristics = try await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)
            hasHDR = characteristics.contains(.containsHDRVideo)
            hasAlpha = characteristics.contains(.containsAlphaChannel)
        } catch {
            // ignore - older APIs may not support these characteristics
        }

        // ftyp atom (MP4 / MOV) — major brand + compatible brands
        let (major, compatible) = parseMP4Brands(url: url)

        return GeneralInfo(
            fileURL: url,
            fileName: url.lastPathComponent,
            fileSize: size,
            containerFormat: containerLabel(forExtension: url.pathExtension),
            containerExtension: url.pathExtension.uppercased(),
            utiType: values.contentType?.identifier,
            duration: durationSec,
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            overallBitrate: bitrate,
            encoder: encoder,
            writingApplication: writingApp,
            hasAlphaChannel: hasAlpha,
            hasHDRVideo: hasHDR,
            majorBrand: major,
            compatibleBrands: compatible
        )
    }

    /// Lit les premiers octets du fichier pour parser l'atom `ftyp` (ISO BMFF / MOV / MP4).
    /// Format : [size 4B BE][type "ftyp"][major brand 4B][minor version 4B][compatible brands N×4B…]
    private static func parseMP4Brands(url: URL) -> (major: String?, compatible: [String]) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return (nil, []) }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 128), data.count >= 16 else { return (nil, []) }
        let bytes = [UInt8](data)
        // Vérifie "ftyp" à l'offset 4
        let type = String(bytes: Array(bytes[4..<8]), encoding: .ascii) ?? ""
        guard type == "ftyp" else { return (nil, []) }
        let size = Int(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        let major = String(bytes: Array(bytes[8..<12]), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var compatible: [String] = []
        let limit = min(max(size, 16), bytes.count)
        var offset = 16
        while offset + 4 <= limit {
            if let s = String(bytes: Array(bytes[offset..<(offset + 4)]), encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !s.isEmpty {
                compatible.append(s)
            }
            offset += 4
        }
        return (major, compatible)
    }

    private static func findMetadataValue(in items: [AVMetadataItem], matching keys: [String]) async -> String? {
        let keysLower = Set(keys.map { $0.lowercased() })
        for item in items {
            let candidates: [String] = [
                item.commonKey?.rawValue,
                (item.key as? String),
                item.identifier?.rawValue
            ].compactMap { $0 }
            if candidates.contains(where: { keysLower.contains($0.lowercased()) }) {
                if let s = (try? await item.load(.stringValue)) ?? nil, !s.isEmpty {
                    return s
                }
            }
        }
        return nil
    }

    private static func containerLabel(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "mov", "qt": return "QuickTime (MOV)"
        case "mp4", "m4v": return "MPEG-4 (MP4)"
        case "m4a": return "MPEG-4 Audio (M4A)"
        case "mkv": return "Matroska (MKV)"
        case "mxf": return "Material Exchange Format (MXF)"
        case "avi": return "AVI"
        case "wav": return "WAVE (WAV)"
        case "aiff", "aif": return "AIFF"
        case "flac": return "FLAC"
        case "mp3": return "MPEG-1 Layer III (MP3)"
        case "aac": return "AAC (ADTS)"
        case "caf": return "Core Audio Format (CAF)"
        case "ogg", "oga": return "Ogg"
        case "webm": return "WebM"
        case "ts", "m2ts", "mts": return "MPEG-TS"
        default: return ext.isEmpty ? "Inconnu" : ext.uppercased()  // "Inconnu" est traduit côté View
        }
    }

    // MARK: Video

    /// `kCMFormatDescriptionExtension_Depth` retourne la profondeur **totale par pixel**
    /// (ex : 24 = 3 composantes × 8 bits). On la ramène à la profondeur par composante,
    /// qui est le terme standard utilisé par les pros (8 / 10 / 12 / 16 bits).
    private static func normalizedComponentDepth(_ totalDepth: Int?, chromaSubsampling: String?) -> Int? {
        guard let total = totalDepth, total > 0 else { return nil }
        let components: Int
        if let sub = chromaSubsampling, sub.contains("4:4:4:4") {
            components = 4
        } else {
            components = 3
        }
        let perComp = total / components
        // Filtrer les valeurs aberrantes
        guard [8, 10, 12, 16].contains(perComp) else { return nil }
        return perComp
    }

    private static func analyzeVideo(track: AVAssetTrack) async throws -> VideoTrack? {
        let formatDescs = try await track.load(.formatDescriptions)
        guard let formatDesc = formatDescs.first else { return nil }

        let subtype = CMFormatDescriptionGetMediaSubType(formatDesc)
        let fourCC = subtype.fourCCString
        let codecName = CodecNames.name(for: fourCC, mediaType: "video")

        let dims = CMVideoFormatDescriptionGetDimensions(formatDesc)

        async let naturalSize = track.load(.naturalSize)
        async let fps = track.load(.nominalFrameRate)
        async let rate = track.load(.estimatedDataRate)
        async let mfd = track.load(.minFrameDuration)
        async let timeRange = track.load(.timeRange)

        let (size, fpsValue, rateValue, mfdValue, tr) = try await (naturalSize, fps, rate, mfd, timeRange)

        let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] ?? [:]
        let primariesRaw = extensions[kCMFormatDescriptionExtension_ColorPrimaries as String] as? String
        let transferRaw = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
        let matrixRaw = extensions[kCMFormatDescriptionExtension_YCbCrMatrix as String] as? String
        let depthFromExt = normalizedComponentDepth(
            (extensions[kCMFormatDescriptionExtension_Depth as String] as? NSNumber)?.intValue,
            chromaSubsampling: CodecNames.chromaSubsampling(forVideoFourCC: fourCC)
        )

        let isHDR = ColorMetadataNames.isHDR(transferRaw: transferRaw)
        let hdrFormat = ColorMetadataNames.hdrFormat(transferRaw: transferRaw, codecFourCC: fourCC)

        // Color range (Full vs Limited) — clé de traduction, localisée au render
        let fullRange = (extensions[kCMFormatDescriptionExtension_FullRangeVideo as String] as? Bool) ?? false
        let colorRange = fullRange ? "Plage complète (Full / PC)" : "Plage limitée (Limited / TV)"

        // Pixel Aspect Ratio
        var pasp: Double? = nil
        if let paspDict = extensions[kCMFormatDescriptionExtension_PixelAspectRatio as String] as? [String: Any] {
            let h = (paspDict[kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String] as? NSNumber)?.intValue ?? 1
            let v = (paspDict[kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String] as? NSNumber)?.intValue ?? 1
            if v > 0 { pasp = Double(h) / Double(v) }
        }

        // Field order
        let fieldOrder = parseFieldOrder(extensions: extensions)

        // Codec profile (avcC / hvcC)
        let codecProfile = parseCodecProfile(fourCC: fourCC, extensions: extensions)

        // HDR mastering data
        let (maxCLL, maxFALL) = parseContentLightLevel(extensions: extensions)
        let hasMDCV = extensions[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] != nil

        // Total frames (estimation)
        let totalFrames: Int?
        if fpsValue > 0 {
            let secs = CMTimeGetSeconds(tr.duration)
            totalFrames = secs > 0 ? Int((secs * Double(fpsValue)).rounded()) : nil
        } else {
            totalFrames = nil
        }

        let minDur: Double? = mfdValue.isValid && mfdValue.seconds > 0 ? mfdValue.seconds : nil

        // Average frame size (octets) = bitrate * duration_per_frame / 8
        var avgFrameSize: Int64? = nil
        if rateValue > 0, fpsValue > 0 {
            avgFrameSize = Int64((Double(rateValue) / Double(fpsValue)) / 8.0)
        }

        // Track-level metadata (camera, RAW, ARRI/RED/Sony …)
        let trackMeta = (try? await track.load(.metadata)) ?? []
        let trackMetaItems = await collectMetadata(common: [], all: trackMeta)

        // Dérivations supplémentaires (1, 2, 3, 4, 5, 9)
        let colorSpace = CodecNames.colorSpace(forVideoFourCC: fourCC)
        let compressionMode = CodecNames.compressionMode(forFourCC: fourCC, mediaType: "video")
        let codecLongName = CodecNames.longName(for: fourCC)
        var bitsPerPixelFrame: Double? = nil
        if rateValue > 0, fpsValue > 0, dims.width > 0, dims.height > 0 {
            let pixels = Double(dims.width) * Double(dims.height)
            let bpf = Double(rateValue) / (pixels * Double(fpsValue))
            if bpf.isFinite, bpf > 0, bpf < 100 { bitsPerPixelFrame = bpf }
        }
        var frameRateMode: String? = nil
        if let minDur, fpsValue > 0 {
            let expected = 1.0 / Double(fpsValue)
            let delta = abs(minDur - expected)
            frameRateMode = (delta / expected < 0.05) ? "Constant (CFR)" : "Variable (VFR)"
        }
        let trackDurationSec = CMTimeGetSeconds(tr.duration).isFinite ? CMTimeGetSeconds(tr.duration) : nil

        return VideoTrack(
            trackID: track.trackID,
            codecFourCC: fourCC,
            codecName: codecName,
            codecProfile: codecProfile,
            width: Int(dims.width),
            height: Int(dims.height),
            displayWidth: Int(size.width),
            displayHeight: Int(size.height),
            pixelAspectRatio: pasp,
            nominalFrameRate: fpsValue,
            minFrameDuration: minDur,
            estimatedDataRate: rateValue,
            totalFrames: totalFrames,
            bitDepth: depthFromExt ?? CodecNames.bitDepth(forVideoFourCC: fourCC),
            colorPrimaries: ColorMetadataNames.primariesLabel(primariesRaw),
            transferFunction: ColorMetadataNames.transferLabel(transferRaw),
            yCbCrMatrix: ColorMetadataNames.matrixLabel(matrixRaw),
            colorRange: colorRange,
            chromaSubsampling: CodecNames.chromaSubsampling(forVideoFourCC: fourCC),
            pixelFormat: fourCC,
            fieldOrder: fieldOrder,
            isHDR: isHDR,
            hdrFormat: hdrFormat,
            maxCLL: maxCLL,
            maxFALL: maxFALL,
            hasMasteringDisplay: hasMDCV,
            averageFrameSize: avgFrameSize,
            trackMetadata: trackMetaItems,
            colorSpace: colorSpace,
            compressionMode: compressionMode,
            bitsPerPixelFrame: bitsPerPixelFrame,
            frameRateMode: frameRateMode,
            codecLongName: codecLongName,
            trackDuration: trackDurationSec
        )
    }

    // MARK: Video helpers

    private static func parseFieldOrder(extensions: [String: Any]) -> String? {
        let fieldCount = (extensions[kCMFormatDescriptionExtension_FieldCount as String] as? NSNumber)?.intValue
        if fieldCount == 1 { return "Progressif" }
        if fieldCount == 2 {
            let detail = extensions[kCMFormatDescriptionExtension_FieldDetail as String] as? String
            switch detail {
            case String(kCMFormatDescriptionFieldDetail_TemporalTopFirst):
                return "Entrelacé — trame haute d'abord (TFF)"
            case String(kCMFormatDescriptionFieldDetail_TemporalBottomFirst):
                return "Entrelacé — trame basse d'abord (BFF)"
            case String(kCMFormatDescriptionFieldDetail_SpatialFirstLineEarly),
                 String(kCMFormatDescriptionFieldDetail_SpatialFirstLineLate):
                return "Entrelacé (spatial)"
            default:
                return "Entrelacé"
            }
        }
        return nil
    }

    private static func parseCodecProfile(fourCC: String, extensions: [String: Any]) -> String? {
        guard let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any] else { return nil }
        let cc = fourCC.lowercased()
        if cc == "avc1", let data = atoms["avcC"] as? Data {
            return parseAVCProfile(data)
        }
        if (cc == "hvc1" || cc == "hev1" || cc == "dvh1" || cc == "dvhe"), let data = atoms["hvcC"] as? Data {
            return parseHEVCProfile(data)
        }
        return nil
    }

    private static func parseAVCProfile(_ data: Data) -> String? {
        guard data.count >= 4 else { return nil }
        let bytes = Array(data)  // ré-aligne sur l'index 0 si la Data vient d'une slice
        let profileIdc = bytes[1]
        let levelIdc = bytes[3]
        let profileName: String
        switch profileIdc {
        case 66: profileName = "Baseline"
        case 77: profileName = "Main"
        case 88: profileName = "Extended"
        case 100: profileName = "High"
        case 110: profileName = "High 10"
        case 122: profileName = "High 4:2:2"
        case 244: profileName = "High 4:4:4 Predictive"
        case 44: profileName = "CAVLC 4:4:4 Intra"
        default: profileName = "Profile \(profileIdc)"
        }
        let major = levelIdc / 10
        let minor = levelIdc % 10
        return "\(profileName) @L\(major).\(minor)"
    }

    private static func parseHEVCProfile(_ data: Data) -> String? {
        guard data.count >= 13 else { return nil }
        let bytes = Array(data)
        let profileIdc = bytes[1] & 0x1F
        let tierFlag = (bytes[1] >> 5) & 0x01
        let levelIdc = bytes[12]
        let profileName: String
        switch profileIdc {
        case 1: profileName = "Main"
        case 2: profileName = "Main 10"
        case 3: profileName = "Main Still Picture"
        case 4: profileName = "REXT"
        default: profileName = "Profile \(profileIdc)"
        }
        let tier = tierFlag == 1 ? "High" : "Main"
        let major = levelIdc / 30
        let minor = (levelIdc % 30) / 3
        return "\(profileName) @L\(major).\(minor) (\(tier) tier)"
    }

    private static func parseContentLightLevel(extensions: [String: Any]) -> (Int?, Int?) {
        guard let data = extensions[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] as? Data,
              data.count >= 4 else { return (nil, nil) }
        let bytes = Array(data)
        let maxCLL = (Int(bytes[0]) << 8) | Int(bytes[1])
        let maxFALL = (Int(bytes[2]) << 8) | Int(bytes[3])
        return (maxCLL, maxFALL)
    }

    // MARK: Audio

    private static func analyzeAudio(track: AVAssetTrack) async throws -> AudioTrack? {
        let formatDescs = try await track.load(.formatDescriptions)
        guard let formatDesc = formatDescs.first else { return nil }

        let subtype = CMFormatDescriptionGetMediaSubType(formatDesc)
        let fourCC = subtype.fourCCString
        let codecName = CodecNames.name(for: fourCC, mediaType: "audio")

        var sampleRate: Double = 0
        var channels: Int = 0
        var bitsPerChannel: Int? = nil
        var isCompressed = true
        var endianness: String? = nil

        if let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            let asbd = asbdPtr.pointee
            sampleRate = asbd.mSampleRate
            channels = Int(asbd.mChannelsPerFrame)
            if asbd.mBitsPerChannel > 0 {
                bitsPerChannel = Int(asbd.mBitsPerChannel)
            }
            isCompressed = asbd.mFormatID != kAudioFormatLinearPCM
            if asbd.mFormatID == kAudioFormatLinearPCM {
                let bigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0
                endianness = bigEndian ? "Big Endian" : "Little Endian"  // clé de traduction
            }
        }

        var layoutDesc: String? = nil
        var channelMap: String? = nil
        var layoutSize: Int = 0
        if let layoutPtr = CMAudioFormatDescriptionGetChannelLayout(formatDesc, sizeOut: &layoutSize) {
            let tag = layoutPtr.pointee.mChannelLayoutTag
            layoutDesc = channelLayoutLabel(tag: tag, channels: channels)
            channelMap = channelMapForTag(tag, channels: channels)
        }

        async let rate = track.load(.estimatedDataRate)
        async let langCode = track.load(.languageCode)
        let (rateValue, language) = try await (rate, langCode)

        let audioProfile = detectAudioProfile(fourCC: fourCC, formatDesc: formatDesc)
        let trackMeta = (try? await track.load(.metadata)) ?? []
        let trackMetaItems = await collectMetadata(common: [], all: trackMeta)

        // Audio dérivés (6, 7, 8, 9)
        let samplesPerFrame = CodecNames.samplesPerFrame(forAudioFourCC: fourCC, audioProfile: audioProfile)
        let trackTR = (try? await track.load(.timeRange)) ?? .zero
        let trackDurSec = CMTimeGetSeconds(trackTR.duration)
        let trackDurationSec: Double? = trackDurSec.isFinite ? trackDurSec : nil
        var totalSamples: Int64? = nil
        if sampleRate > 0, let dur = trackDurationSec, dur > 0 {
            let ts = sampleRate * dur
            if ts.isFinite, ts < Double(Int64.max) { totalSamples = Int64(ts) }
        }
        let codecIDLong = CodecNames.codecIDLong(forAudioFourCC: fourCC, audioProfile: audioProfile)

        return AudioTrack(
            trackID: track.trackID,
            codecFourCC: fourCC,
            codecName: codecName,
            channelCount: channels,
            channelLayout: layoutDesc,
            channelMap: channelMap,
            sampleRate: sampleRate,
            bitsPerChannel: bitsPerChannel,
            estimatedDataRate: rateValue,
            isCompressed: isCompressed,
            endianness: endianness,
            language: language,
            audioProfile: audioProfile,
            trackMetadata: trackMetaItems,
            samplesPerFrame: samplesPerFrame,
            totalSamples: totalSamples,
            codecIDLong: codecIDLong,
            trackDuration: trackDurationSec
        )
    }

    private static func detectAudioProfile(fourCC: String, formatDesc: CMFormatDescription) -> String? {
        let cc = fourCC.lowercased()
        if cc == "mp4a" {
            // AAC : on lit l'objectType depuis l'esds atom
            let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] ?? [:]
            if let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] as? [String: Any],
               let esds = atoms["esds"] as? Data,
               let profile = parseAACProfile(esds) {
                return profile
            }
            return "AAC"
        }
        if cc == "ac-3" { return "Dolby Digital (AC-3)" }
        if cc == "ec-3" { return "Dolby Digital Plus (E-AC-3)" }
        if cc == "alac" { return "Apple Lossless" }
        if cc == "flac" { return "FLAC" }
        if cc == "opus" { return "Opus" }
        return nil
    }

    /// Recherche l'objectTypeIndication dans un atom esds AAC.
    /// Format simplifié : on cherche les tags `0x05` (DecSpecificInfo).
    private static func parseAACProfile(_ data: Data) -> String? {
        guard data.count > 4 else { return nil }
        let bytes = Array(data)  // ré-aligne sur 0 si Data vient d'une slice
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] == 0x05 {
                var j = i + 1
                while j < bytes.count && (bytes[j] & 0x80) != 0 { j += 1 }
                j += 1
                if j < bytes.count {
                    let firstByte = bytes[j]
                    let audioObjectType = Int((firstByte >> 3) & 0x1F)
                    switch audioObjectType {
                    case 1: return "AAC Main"
                    case 2: return "AAC LC"
                    case 3: return "AAC SSR"
                    case 4: return "AAC LTP"
                    case 5: return "HE-AAC (SBR)"
                    case 6: return "AAC Scalable"
                    case 7: return "TwinVQ"
                    case 17: return "ER AAC LC"
                    case 19: return "ER AAC LTP"
                    case 20: return "ER AAC Scalable"
                    case 23: return "ER AAC LD"
                    case 29: return "HE-AAC v2 (PS)"
                    default: return "AAC type \(audioObjectType)"
                    }
                }
            }
            i += 1
        }
        return nil
    }

    private static func channelLayoutLabel(tag: AudioChannelLayoutTag, channels: Int) -> String? {
        switch tag {
        case kAudioChannelLayoutTag_Mono: return "Mono"
        case kAudioChannelLayoutTag_Stereo, kAudioChannelLayoutTag_StereoHeadphones: return "Stereo (L R)"
        case kAudioChannelLayoutTag_MPEG_5_1_A,
             kAudioChannelLayoutTag_MPEG_5_1_B,
             kAudioChannelLayoutTag_MPEG_5_1_C,
             kAudioChannelLayoutTag_MPEG_5_1_D: return "5.1"
        case kAudioChannelLayoutTag_MPEG_7_1_A,
             kAudioChannelLayoutTag_MPEG_7_1_B,
             kAudioChannelLayoutTag_MPEG_7_1_C: return "7.1"
        case kAudioChannelLayoutTag_MPEG_3_0_A, kAudioChannelLayoutTag_MPEG_3_0_B: return "3.0"
        case kAudioChannelLayoutTag_MPEG_4_0_A, kAudioChannelLayoutTag_MPEG_4_0_B: return "4.0"
        case kAudioChannelLayoutTag_MPEG_5_0_A, kAudioChannelLayoutTag_MPEG_5_0_B,
             kAudioChannelLayoutTag_MPEG_5_0_C, kAudioChannelLayoutTag_MPEG_5_0_D: return "5.0"
        default:
            if channels == 1 { return "Mono" }
            if channels == 2 { return "Stereo" }
            return "\(channels) canaux"  // contient %lld dans la clé xcstrings
        }
    }

    private static func channelMapForTag(_ tag: AudioChannelLayoutTag, channels: Int) -> String? {
        switch tag {
        case kAudioChannelLayoutTag_Mono: return "C"
        case kAudioChannelLayoutTag_Stereo, kAudioChannelLayoutTag_StereoHeadphones: return "L R"
        case kAudioChannelLayoutTag_MPEG_3_0_A: return "L R C"
        case kAudioChannelLayoutTag_MPEG_3_0_B: return "C L R"
        case kAudioChannelLayoutTag_MPEG_4_0_A: return "L R C Cs"
        case kAudioChannelLayoutTag_MPEG_4_0_B: return "C L R Cs"
        case kAudioChannelLayoutTag_MPEG_5_0_A: return "L R C Ls Rs"
        case kAudioChannelLayoutTag_MPEG_5_0_B: return "L R Ls Rs C"
        case kAudioChannelLayoutTag_MPEG_5_0_C: return "L C R Ls Rs"
        case kAudioChannelLayoutTag_MPEG_5_0_D: return "C L R Ls Rs"
        case kAudioChannelLayoutTag_MPEG_5_1_A: return "L R C LFE Ls Rs"
        case kAudioChannelLayoutTag_MPEG_5_1_B: return "L R Ls Rs C LFE"
        case kAudioChannelLayoutTag_MPEG_5_1_C: return "L C R Ls Rs LFE"
        case kAudioChannelLayoutTag_MPEG_5_1_D: return "C L R Ls Rs LFE"
        case kAudioChannelLayoutTag_MPEG_7_1_A: return "L R C LFE Ls Rs Lc Rc"
        case kAudioChannelLayoutTag_MPEG_7_1_B: return "C Lc Rc L R Ls Rs LFE"
        case kAudioChannelLayoutTag_MPEG_7_1_C: return "L R C LFE Ls Rs Rls Rrs"
        default:
            if channels == 1 { return "C" }
            if channels == 2 { return "L R" }
            return nil
        }
    }

    // MARK: Subtitles

    private static func analyzeSubtitle(track: AVAssetTrack) async throws -> SubtitleTrack {
        let formatDescs = try await track.load(.formatDescriptions)
        var fourCC = "----"
        if let formatDesc = formatDescs.first {
            fourCC = CMFormatDescriptionGetMediaSubType(formatDesc).fourCCString
        }
        let language = try await track.load(.languageCode)
        let isCC = track.mediaType == .closedCaption
        return SubtitleTrack(
            trackID: track.trackID,
            format: CodecNames.name(for: fourCC, mediaType: "video"),
            language: language,
            isClosedCaption: isCC
        )
    }

    // MARK: Timecode

    private static func analyzeTimecode(track: AVAssetTrack, asset: AVURLAsset) async throws -> TimecodeInfo {
        let fps = try await track.load(.nominalFrameRate)
        let formatDescs = try await track.load(.formatDescriptions)
        var dropFrame = false
        if let formatDesc = formatDescs.first {
            let flags = CMTimeCodeFormatDescriptionGetTimeCodeFlags(formatDesc)
            dropFrame = (flags & UInt32(kCMTimeCodeFlag_DropFrame)) != 0
        }

        let timeRange = try await track.load(.timeRange)
        let durationSec = CMTimeGetSeconds(timeRange.duration)

        var startTC: String? = nil
        var endTC: String? = nil
        var startFrameForEnd: Int = 0
        if let startFrame = readStartFrameNumber(track: track, asset: asset), fps > 0 {
            startTC = framesToTimecode(frames: Int(startFrame), fps: fps, dropFrame: dropFrame)
            startFrameForEnd = Int(startFrame)
        } else {
            // Fallback : métadonnées QuickTime du track et de l'asset
            let trackMeta = (try? await track.load(.metadata)) ?? []
            let assetMeta = (try? await asset.load(.metadata)) ?? []
            if let tcString = await startTimecodeFromMetadata(trackMeta + assetMeta) {
                mediaLog.info("TMCD: startTC depuis metadata = \(tcString, privacy: .public)")
                startTC = tcString
            } else {
                mediaLog.info("TMCD: aucun timecode dans les metadonnees non plus")
            }
        }
        if startTC != nil, fps > 0, durationSec.isFinite, durationSec > 0 {
            let durFrames = Int((durationSec * Double(fps)).rounded())
            endTC = framesToTimecode(frames: startFrameForEnd + durFrames, fps: fps, dropFrame: dropFrame)
        }

        return TimecodeInfo(
            startTimecode: startTC,
            endTimecode: endTC,
            frameRate: fps,
            dropFrame: dropFrame,
            trackID: track.trackID
        )
    }

    private static func readStartFrameNumber(track: AVAssetTrack, asset: AVURLAsset) -> UInt32? {
        guard let reader = try? AVAssetReader(asset: asset) else {
            mediaLog.error("TMCD: AVAssetReader init failed")
            return nil
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else {
            mediaLog.error("TMCD: cannot add reader output")
            return nil
        }
        reader.add(output)
        guard reader.startReading() else {
            mediaLog.error("TMCD: startReading failed status=\(reader.status.rawValue) err=\(reader.error?.localizedDescription ?? "nil", privacy: .public)")
            return nil
        }
        defer { reader.cancelReading() }

        // Boucle sur les samples : certains TMCD ont des samples marqueurs sans data buffer
        // au début. On lit jusqu'à 10 samples max pour trouver le premier avec un buffer.
        var samplesRead = 0
        while samplesRead < 10, let sample = output.copyNextSampleBuffer() {
            samplesRead += 1

            // Tentative 1 : DataBuffer + CopyDataBytes
            if let bb = CMSampleBufferGetDataBuffer(sample),
               CMBlockBufferGetDataLength(bb) >= 4 {
                var bytes: [UInt8] = [0, 0, 0, 0]
                let status = bytes.withUnsafeMutableBytes { rawBuf -> OSStatus in
                    guard let base = rawBuf.baseAddress else { return -1 }
                    return CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: 4, destination: base)
                }
                if status == noErr {
                    let frame = (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
                    mediaLog.info("TMCD: startFrame = \(frame, privacy: .public) (DataBuffer, sample #\(samplesRead, privacy: .public))")
                    return frame
                }
            }

            // Tentative 2 : GetDataPointer (chemin alternatif)
            if let bb = CMSampleBufferGetDataBuffer(sample) {
                var lengthAtOffset = 0
                var totalLength = 0
                var dataPointer: UnsafeMutablePointer<CChar>?
                let status = CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
                if status == noErr, let ptr = dataPointer, totalLength >= 4 {
                    let b0 = UInt8(bitPattern: ptr[0])
                    let b1 = UInt8(bitPattern: ptr[1])
                    let b2 = UInt8(bitPattern: ptr[2])
                    let b3 = UInt8(bitPattern: ptr[3])
                    let frame = (UInt32(b0) << 24) | (UInt32(b1) << 16) | (UInt32(b2) << 8) | UInt32(b3)
                    mediaLog.info("TMCD: startFrame = \(frame, privacy: .public) (GetDataPointer, sample #\(samplesRead, privacy: .public))")
                    return frame
                }
            }
        }

        mediaLog.error("TMCD: \(samplesRead, privacy: .public) samples lus, aucun n'a fourni de DataBuffer exploitable")
        return nil
    }

    /// Cherche un timecode dans les métadonnées QuickTime (`com.apple.quicktime.timecode`)
    /// — fallback quand AVAssetReader ne donne pas accès aux samples TMCD.
    private static func startTimecodeFromMetadata(_ metadata: [AVMetadataItem]) async -> String? {
        for item in metadata {
            let id = item.identifier?.rawValue ?? ""
            let key = (item.key as? String) ?? ""
            if id.contains("timecode") || id.contains("TimeCode") || key.lowercased().contains("timecode") {
                if let s = (try? await item.load(.stringValue)) ?? nil, !s.isEmpty {
                    return s
                }
            }
        }
        return nil
    }

    /// Convertit un nombre de frames en timecode SMPTE HH:MM:SS:FF (ou HH:MM:SS;FF en drop-frame).
    /// Gère 23.976/24/25/29.97 NDF/29.97 DF/30/50/59.94 NDF/59.94 DF/60.
    private static func framesToTimecode(frames totalFrames: Int, fps: Float, dropFrame: Bool) -> String {
        let fpsBase = Int(fps.rounded())
        guard fpsBase > 0 else { return "—" }

        var frame = max(0, totalFrames)  // clamp neg
        var separator = ":"

        if dropFrame && (fpsBase == 30 || fpsBase == 60) {
            // SMPTE drop frame : drops 2 frames/min @ 29.97 (4 @ 59.94), except every 10th minute.
            let dropFramesPerMin = fpsBase == 30 ? 2 : 4
            let framesPerMin = fpsBase * 60 - dropFramesPerMin
            let framesPer10Min = fpsBase * 600 - 9 * dropFramesPerMin

            let d = frame / framesPer10Min
            let m = frame % framesPer10Min
            if m >= dropFramesPerMin {  // SMPTE : >= (et non >)
                frame += 9 * dropFramesPerMin * d + dropFramesPerMin * ((m - dropFramesPerMin) / framesPerMin)
            } else {
                frame += 9 * dropFramesPerMin * d
            }
            separator = ";"
        }

        let h = (frame / (3600 * fpsBase)) % 24
        let mm = (frame / (60 * fpsBase)) % 60
        let s = (frame / fpsBase) % 60
        let f = frame % fpsBase
        return String(format: "%02d:%02d:%02d\(separator)%02d", h, mm, s, f)
    }

    // MARK: Metadata

    private static func collectMetadata(common: [AVMetadataItem], all: [AVMetadataItem]) async -> [MetadataItem] {
        var items: [MetadataItem] = []
        var seen = Set<String>()

        for item in common {
            guard let key = item.commonKey?.rawValue else { continue }
            let value = await stringValue(of: item)
            guard !value.isEmpty else { continue }
            let dedup = "common.\(key)"
            if seen.contains(dedup) { continue }
            seen.insert(dedup)
            items.append(MetadataItem(key: key, value: value, keySpace: "common"))
        }

        for item in all {
            let keySpace = item.keySpace?.rawValue
            let keyStr: String
            if let k = item.commonKey?.rawValue {
                keyStr = k
            } else if let k = item.key as? String {
                keyStr = k
            } else if let k = item.identifier?.rawValue {
                keyStr = k
            } else {
                continue
            }
            let value = await stringValue(of: item)
            guard !value.isEmpty else { continue }
            let dedup = "\(keySpace ?? "any").\(keyStr)"
            if seen.contains(dedup) { continue }
            seen.insert(dedup)
            items.append(MetadataItem(key: keyStr, value: value, keySpace: keySpace))
        }

        return items
    }

    private static func stringValue(of item: AVMetadataItem) async -> String {
        do {
            if let s = try await item.load(.stringValue), !s.isEmpty { return s }
            if let n = try await item.load(.numberValue) { return n.stringValue }
            if let d = try await item.load(.dateValue) {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .medium
                return f.string(from: d)
            }
            if let data = try await item.load(.dataValue) { return "<\(data.count) octets>" }
        } catch {
            return ""
        }
        return ""
    }
}

nonisolated extension FourCharCode {
    var fourCCString: String {
        let bytes: [UInt8] = [
            UInt8((self >> 24) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8(self & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "----"
    }
}
