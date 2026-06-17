import Foundation

// MARK: - Modèles

/// Sévérité d'une règle de conformité.
nonisolated enum ConformitySeverity: String, Sendable, Hashable {
    case mandatory  // bloque la livraison
    case recommended  // important mais pas bloquant
    case informational
}

/// État final d'une règle après évaluation.
nonisolated enum ConformityStatus: String, Sendable, Hashable {
    case pass
    case fail
    case warning
    case notApplicable
}

/// Résultat d'évaluation d'une règle.
nonisolated struct ConformityResult: Identifiable, Hashable, Sendable {
    let id = UUID()
    let ruleID: String
    let ruleTitle: String
    let expected: String
    let actual: String
    let status: ConformityStatus
    let severity: ConformitySeverity
    let explanation: String
}

/// Préréglage : nom + liste de règles à appliquer.
nonisolated struct ConformityPreset: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String
    let rules: [ConformityRule]
}

/// Règle de conformité (function-based pour flexibilité).
nonisolated struct ConformityRule: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let severity: ConformitySeverity
    let expectedHumanReadable: String
    let explanation: String
    /// Évalue la règle contre une analyse média. Retourne (passed, actualValue).
    let evaluator: @Sendable (MediaAnalysis) -> (ConformityStatus, String)

    static func == (lhs: ConformityRule, rhs: ConformityRule) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Helpers de règles

nonisolated enum RuleBuilders {

    static func videoCodec(in codecs: Set<String>) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first else { return (.notApplicable, "—") }
            let name = v.codecName.lowercased()
            let match = codecs.contains { name.contains($0.lowercased()) }
            return (match ? .pass : .fail, v.codecName)
        }
    }

    static func minResolution(width: Int, height: Int) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first else { return (.notApplicable, "—") }
            let ok = v.width >= width && v.height >= height
            return (ok ? .pass : .fail, "\(v.width)×\(v.height)")
        }
    }

    static func exactResolution(width: Int, height: Int) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first else { return (.notApplicable, "—") }
            let ok = v.width == width && v.height == height
            return (ok ? .pass : .fail, "\(v.width)×\(v.height)")
        }
    }

    static func fpsIn(_ allowed: [Float]) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first else { return (.notApplicable, "—") }
            let ok = allowed.contains { abs(v.nominalFrameRate - $0) < 0.05 }
            return (ok ? .pass : .fail, String(format: "%.3f fps", v.nominalFrameRate))
        }
    }

    static func minBitDepth(_ minDepth: Int) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, let d = v.bitDepth else { return (.notApplicable, "—") }
            return (d >= minDepth ? .pass : .fail, "\(d) bits")
        }
    }

    static func chromaSubsamplingIn(_ allowed: Set<String>) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, let cs = v.chromaSubsampling else { return (.notApplicable, "—") }
            return (allowed.contains(cs) ? .pass : .fail, cs)
        }
    }

    static func colorPrimariesContains(_ keyword: String) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, let p = v.colorPrimaries else { return (.notApplicable, "—") }
            return (p.contains(keyword) ? .pass : .fail, p)
        }
    }

    static func transferContains(_ keyword: String) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, let t = v.transferFunction else { return (.notApplicable, "—") }
            return (t.contains(keyword) ? .pass : .fail, t)
        }
    }

    static func hdr10Mastering() -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first else { return (.notApplicable, "—") }
            let ok = v.isHDR && v.maxCLL != nil && v.maxFALL != nil && v.hasMasteringDisplay
            let parts = [
                v.maxCLL.map { "MaxCLL \($0)" },
                v.maxFALL.map { "MaxFALL \($0)" },
                v.hasMasteringDisplay ? "MDCV ✓" : nil
            ].compactMap { $0 }
            return (ok ? .pass : .fail, parts.isEmpty ? "Aucune métadonnée HDR" : parts.joined(separator: " · "))
        }
    }

    static func audioCodec(in codecs: Set<String>) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first else { return (.notApplicable, "—") }
            let name = a.codecName.lowercased()
            let match = codecs.contains { name.contains($0.lowercased()) }
            return (match ? .pass : .fail, a.codecName)
        }
    }

    static func minSampleRate(_ minHz: Double) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first else { return (.notApplicable, "—") }
            return (a.sampleRate >= minHz ? .pass : .fail, String(format: "%.1f kHz", a.sampleRate / 1000))
        }
    }

    static func minChannels(_ count: Int) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first else { return (.notApplicable, "—") }
            return (a.channelCount >= count ? .pass : .fail, "\(a.channelCount)")
        }
    }

    static func lufsInRange(low: Double, high: Double) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first, let lufs = a.integratedLUFS else { return (.notApplicable, "—") }
            let ok = lufs >= low && lufs <= high
            return (ok ? .pass : .fail, String(format: "%.1f LUFS", lufs))
        }
    }

    static func truePeakBelow(_ dbtp: Double) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first, let tp = a.truePeakDBTP else { return (.notApplicable, "—") }
            return (tp <= dbtp ? .pass : .fail, String(format: "%.1f dBTP", tp))
        }
    }

    static func audioBitDepth(min: Int) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first, let bd = a.bitsPerChannel else { return (.notApplicable, "—") }
            return (bd >= min ? .pass : .fail, "\(bd) bits")
        }
    }

    static func channelCount(equals n: Int) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first else { return (.notApplicable, "—") }
            return (a.channelCount == n ? .pass : .fail, "\(a.channelCount)")
        }
    }

    static func channelCount(in counts: Set<Int>) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let a = analysis.audioTracks.first else { return (.notApplicable, "—") }
            return (counts.contains(a.channelCount) ? .pass : .fail, "\(a.channelCount)")
        }
    }

    static func containerExtensionIn(_ exts: Set<String>) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            let e = analysis.general.containerExtension.lowercased()
            return (exts.map { $0.lowercased() }.contains(e) ? .pass : .fail, analysis.general.containerExtension)
        }
    }

    static func matrixContains(_ keyword: String) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, let m = v.yCbCrMatrix else { return (.notApplicable, "—") }
            return (m.contains(keyword) ? .pass : .fail, m)
        }
    }

    static func colorRangeContains(_ keyword: String) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, let cr = v.colorRange else { return (.notApplicable, "—") }
            return (cr.localizedCaseInsensitiveContains(keyword) ? .pass : .fail, cr)
        }
    }

    static func progressiveScan(severity: ConformityStatus = .fail) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, let f = v.fieldOrder else { return (.notApplicable, "—") }
            let prog = f.localizedCaseInsensitiveContains("progress")
            return (prog ? .pass : severity, f)
        }
    }

    static func minimumBitrate(_ minBitsPerSec: Double) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, v.estimatedDataRate > 0 else { return (.notApplicable, "—") }
            let mbps = Double(v.estimatedDataRate) / 1_000_000
            return (Double(v.estimatedDataRate) >= minBitsPerSec ? .pass : .fail, String(format: "%.1f Mb/s", mbps))
        }
    }

    static func maximumBitrate(_ maxBitsPerSec: Double) -> @Sendable (MediaAnalysis) -> (ConformityStatus, String) {
        { analysis in
            guard let v = analysis.videoTracks.first, v.estimatedDataRate > 0 else { return (.notApplicable, "—") }
            let mbps = Double(v.estimatedDataRate) / 1_000_000
            return (Double(v.estimatedDataRate) <= maxBitsPerSec ? .pass : .warning, String(format: "%.1f Mb/s", mbps))
        }
    }
}

// MARK: - Préréglages embarqués

nonisolated enum ConformityPresets {

    static let allBuiltIn: [ConformityPreset] = [
        netflix4KHDR10,
        netflix4KSDR,
        broadcastEBU_R128,
        dcpFeature,
        youtube4K,
        proResHQDelivery,
        webHTML5
    ]

    // MARK: Netflix 4K HDR10
    static let netflix4KHDR10 = ConformityPreset(
        id: "netflix.4k.hdr10",
        name: "Netflix 4K HDR10",
        summary: "Spécifications de livraison pour les originaux Netflix en HDR10 (4K UHD).",
        rules: [
            ConformityRule(
                id: "video.codec",
                title: "Codec vidéo",
                severity: .mandatory,
                expectedHumanReadable: "HEVC (H.265)",
                explanation: "Netflix exige HEVC pour le HDR10. AVC n'est pas accepté.",
                evaluator: RuleBuilders.videoCodec(in: ["HEVC", "H.265"])
            ),
            ConformityRule(
                id: "video.resolution",
                title: "Résolution",
                severity: .mandatory,
                expectedHumanReadable: "3840×2160 (4K UHD)",
                explanation: "Le master HDR10 Netflix doit être en 4K UHD natif.",
                evaluator: RuleBuilders.exactResolution(width: 3840, height: 2160)
            ),
            ConformityRule(
                id: "video.fps",
                title: "Fréquence d'images",
                severity: .mandatory,
                expectedHumanReadable: "23.976, 24, 25, 29.97 ou 30 fps",
                explanation: "Cadences cinéma/broadcast standard. 48/60 acceptées avec accord préalable.",
                evaluator: RuleBuilders.fpsIn([23.976, 24, 25, 29.97, 30])
            ),
            ConformityRule(
                id: "video.bitdepth",
                title: "Profondeur",
                severity: .mandatory,
                expectedHumanReadable: "≥ 10 bits",
                explanation: "HDR10 = 10 bits minimum par composante.",
                evaluator: RuleBuilders.minBitDepth(10)
            ),
            ConformityRule(
                id: "video.chroma",
                title: "Sous-échantillonnage",
                severity: .mandatory,
                expectedHumanReadable: "4:2:0",
                explanation: "Standard Netflix pour la distribution HEVC.",
                evaluator: RuleBuilders.chromaSubsamplingIn(["4:2:0"])
            ),
            ConformityRule(
                id: "color.primaries",
                title: "Primaries",
                severity: .mandatory,
                expectedHumanReadable: "BT.2020",
                explanation: "HDR10 utilise le gamut élargi Rec. 2020.",
                evaluator: RuleBuilders.colorPrimariesContains("2020")
            ),
            ConformityRule(
                id: "color.transfer",
                title: "Fonction de transfert",
                severity: .mandatory,
                expectedHumanReadable: "SMPTE ST 2084 (PQ)",
                explanation: "Le PQ est la courbe HDR10 standard.",
                evaluator: RuleBuilders.transferContains("PQ")
            ),
            ConformityRule(
                id: "color.hdr",
                title: "Métadonnées HDR statiques",
                severity: .mandatory,
                expectedHumanReadable: "MaxCLL + MaxFALL + Mastering Display Color Volume",
                explanation: "Sans MDCV/MaxCLL/MaxFALL, le HDR10 est invalide chez Netflix.",
                evaluator: RuleBuilders.hdr10Mastering()
            ),
            ConformityRule(
                id: "audio.sampleRate",
                title: "Fréquence audio",
                severity: .mandatory,
                expectedHumanReadable: "≥ 48 kHz",
                explanation: "Master Netflix exige 48 kHz minimum.",
                evaluator: RuleBuilders.minSampleRate(48000)
            ),
            ConformityRule(
                id: "audio.channels",
                title: "Canaux audio",
                severity: .recommended,
                expectedHumanReadable: "≥ 6 (5.1) pour mix surround",
                explanation: "Recommandé pour la livraison surround. Stereo accepté pour certains titres.",
                evaluator: RuleBuilders.minChannels(6)
            )
        ]
    )

    // MARK: Netflix 4K SDR
    static let netflix4KSDR = ConformityPreset(
        id: "netflix.4k.sdr",
        name: "Netflix 4K SDR",
        summary: "Livraison Netflix 4K UHD en SDR — Originals Delivery Specifications.",
        rules: [
            ConformityRule(id: "v.codec", title: "Codec vidéo", severity: .mandatory,
                           expectedHumanReadable: "Apple ProRes 422 HQ ou supérieur",
                           explanation: "Netflix exige un master en ProRes 422 HQ minimum pour le 4K SDR.",
                           evaluator: RuleBuilders.videoCodec(in: ["ProRes 422 HQ", "ProRes 4444"])),
            ConformityRule(id: "v.res", title: "Résolution", severity: .mandatory,
                           expectedHumanReadable: "3840×2160 ou 4096×2160",
                           explanation: "Format de livraison Netflix : 4K UHD ou DCI 4K natif.",
                           evaluator: RuleBuilders.minResolution(width: 3840, height: 2160)),
            ConformityRule(id: "v.bd", title: "Profondeur", severity: .mandatory,
                           expectedHumanReadable: "≥ 10 bits",
                           explanation: "10 bits évite le banding sur 4K et conserve l'étalonnage.",
                           evaluator: RuleBuilders.minBitDepth(10)),
            ConformityRule(id: "v.chroma", title: "Sous-échantillonnage", severity: .mandatory,
                           expectedHumanReadable: "4:2:2 ou 4:4:4",
                           explanation: "Pas de 4:2:0 sur un master Netflix.",
                           evaluator: RuleBuilders.chromaSubsamplingIn(["4:2:2", "4:4:4", "4:4:4:4"])),
            ConformityRule(id: "v.fps", title: "FPS", severity: .mandatory,
                           expectedHumanReadable: "23.976 / 24 / 25 / 29.97 / 30",
                           explanation: "Cadences standard. 48/50/60 acceptés avec accord préalable.",
                           evaluator: RuleBuilders.fpsIn([23.976, 24, 25, 29.97, 30])),
            ConformityRule(id: "v.scan", title: "Balayage", severity: .mandatory,
                           expectedHumanReadable: "Progressif",
                           explanation: "Netflix n'accepte pas les masters entrelacés.",
                           evaluator: RuleBuilders.progressiveScan()),
            ConformityRule(id: "c.primaries", title: "Primaries", severity: .mandatory,
                           expectedHumanReadable: "BT.709 ou BT.2020",
                           explanation: "Rec.709 pour SDR. Rec.2020 si le master est gradé wide gamut.",
                           evaluator: { a in
                               guard let p = a.videoTracks.first?.colorPrimaries else { return (.notApplicable, "—") }
                               return ((p.contains("709") || p.contains("2020")) ? .pass : .fail, p)
                           }),
            ConformityRule(id: "c.range", title: "Plage de couleurs", severity: .mandatory,
                           expectedHumanReadable: "Limited (Video range)",
                           explanation: "Master Netflix = limited range (16-235 sur 10 bits).",
                           evaluator: RuleBuilders.colorRangeContains("limit")),
            ConformityRule(id: "a.sr", title: "Sample rate audio", severity: .mandatory,
                           expectedHumanReadable: "48 kHz",
                           explanation: "Standard pro broadcast/cinéma.",
                           evaluator: RuleBuilders.minSampleRate(48000)),
            ConformityRule(id: "a.bd", title: "Profondeur audio", severity: .mandatory,
                           expectedHumanReadable: "24 bits PCM",
                           explanation: "Master Netflix : PCM 24 bits non compressé.",
                           evaluator: RuleBuilders.audioBitDepth(min: 24)),
            ConformityRule(id: "a.channels", title: "Canaux audio", severity: .recommended,
                           expectedHumanReadable: "6 (5.1) ou 8 (7.1)",
                           explanation: "Surround pour master cinéma. Stéréo pour secondaire.",
                           evaluator: RuleBuilders.channelCount(in: [2, 6, 8])),
            ConformityRule(id: "container", title: "Conteneur", severity: .recommended,
                           expectedHumanReadable: "MOV ou MXF",
                           explanation: "Standard de livraison Netflix.",
                           evaluator: RuleBuilders.containerExtensionIn(["mov", "mxf"]))
        ]
    )

    // MARK: EBU R128 (Broadcast)
    static let broadcastEBU_R128 = ConformityPreset(
        id: "broadcast.ebu.r128",
        name: "Broadcast EBU R128 (HD TV)",
        summary: "Norme EBU R128 + R103 pour la TV européenne HD — France TV, BBC, ARD, ZDF, RAI…",
        rules: [
            // AUDIO — Loudness (EBU R128)
            ConformityRule(id: "audio.lufs", title: "Loudness intégré", severity: .mandatory,
                           expectedHumanReadable: "−23 LUFS ±1 LU",
                           explanation: "EBU R128 §2 : −23 LUFS pour la TV. Cible exacte ±1 LU autorisée pour les programmes courts.",
                           evaluator: RuleBuilders.lufsInRange(low: -24, high: -22)),
            ConformityRule(id: "audio.truepeak", title: "True Peak max", severity: .mandatory,
                           expectedHumanReadable: "≤ −1 dBTP",
                           explanation: "EBU R128 §6 : crête vraie ≤ −1 dBTP pour éviter le clipping inter-sample après codage lossy.",
                           evaluator: RuleBuilders.truePeakBelow(-1.0)),
            // AUDIO — Format
            ConformityRule(id: "audio.sr", title: "Sample rate audio", severity: .mandatory,
                           expectedHumanReadable: "48 kHz",
                           explanation: "EBU R128 + ITU-R BS.1770 : sample rate broadcast = 48 kHz.",
                           evaluator: RuleBuilders.minSampleRate(48000)),
            ConformityRule(id: "audio.bd", title: "Profondeur audio", severity: .recommended,
                           expectedHumanReadable: "24 bits PCM",
                           explanation: "Format de livraison master broadcast standard.",
                           evaluator: RuleBuilders.audioBitDepth(min: 24)),
            ConformityRule(id: "audio.codec", title: "Codec audio", severity: .recommended,
                           expectedHumanReadable: "PCM ou AC-3 (Dolby Digital)",
                           explanation: "Livraison master = PCM non compressé. AC-3 pour diffusion DVB.",
                           evaluator: RuleBuilders.audioCodec(in: ["PCM", "AC-3", "Dolby Digital", "Linear"])),
            ConformityRule(id: "audio.channels", title: "Canaux audio", severity: .recommended,
                           expectedHumanReadable: "2 (stereo) ou 6 (5.1)",
                           explanation: "Stéréo 2.0 ou surround 5.1 (L R C LFE Ls Rs).",
                           evaluator: RuleBuilders.channelCount(in: [2, 6])),
            // VIDEO — Format
            ConformityRule(id: "video.res", title: "Résolution HD", severity: .mandatory,
                           expectedHumanReadable: "1920×1080 (Full HD)",
                           explanation: "Standard EBU R124 pour la TV HD européenne.",
                           evaluator: RuleBuilders.exactResolution(width: 1920, height: 1080)),
            ConformityRule(id: "video.fps", title: "Fréquence d'images", severity: .mandatory,
                           expectedHumanReadable: "25 fps (Europe) ou 50p",
                           explanation: "EBU 50 Hz : 25i ou 50p selon le type de programme.",
                           evaluator: RuleBuilders.fpsIn([25, 50])),
            ConformityRule(id: "video.bd", title: "Profondeur vidéo", severity: .recommended,
                           expectedHumanReadable: "≥ 8 bits (10 bits master)",
                           explanation: "8 bits diffusion. Master livré en 10 bits pour étalonnage.",
                           evaluator: RuleBuilders.minBitDepth(8)),
            ConformityRule(id: "video.scan", title: "Balayage", severity: .recommended,
                           expectedHumanReadable: "Progressif (1080p) ou entrelacé (1080i)",
                           explanation: "Selon le contrat. La plupart des broadcasters acceptent les deux.",
                           evaluator: RuleBuilders.progressiveScan()),
            // VIDEO — Colorimétrie
            ConformityRule(id: "color.primaries", title: "Primaries", severity: .mandatory,
                           expectedHumanReadable: "BT.709",
                           explanation: "Rec.709 = espace HDTV standard.",
                           evaluator: RuleBuilders.colorPrimariesContains("709")),
            ConformityRule(id: "color.transfer", title: "Transfer", severity: .mandatory,
                           expectedHumanReadable: "BT.709",
                           explanation: "Courbe gamma TV.",
                           evaluator: RuleBuilders.transferContains("709")),
            ConformityRule(id: "color.matrix", title: "Matrice", severity: .mandatory,
                           expectedHumanReadable: "BT.709",
                           explanation: "Matrice YCbCr Rec.709.",
                           evaluator: RuleBuilders.matrixContains("709")),
            ConformityRule(id: "color.range", title: "Plage de couleurs", severity: .mandatory,
                           expectedHumanReadable: "Limited (TV / 16-235)",
                           explanation: "Broadcast = limited range. Full range invalide pour TV.",
                           evaluator: RuleBuilders.colorRangeContains("limit")),
            ConformityRule(id: "video.chroma", title: "Chroma", severity: .recommended,
                           expectedHumanReadable: "4:2:2 (master) ou 4:2:0 (diffusion)",
                           explanation: "Master broadcast = 4:2:2 (XDCAM HD422). Diffusion = 4:2:0.",
                           evaluator: RuleBuilders.chromaSubsamplingIn(["4:2:2", "4:2:0"])),
            // VIDEO — Codec / débit
            ConformityRule(id: "video.codec", title: "Codec vidéo", severity: .recommended,
                           expectedHumanReadable: "XDCAM HD422 / AVC-Intra / ProRes HQ",
                           explanation: "Codecs de livraison broadcast pro.",
                           evaluator: RuleBuilders.videoCodec(in: ["XDCAM", "AVC-Intra", "ProRes", "MPEG-2", "DV"])),
            ConformityRule(id: "video.bitrate", title: "Débit vidéo master", severity: .recommended,
                           expectedHumanReadable: "≥ 50 Mb/s",
                           explanation: "XDCAM HD422 = 50 Mb/s. AVC-Intra 100 = 100 Mb/s.",
                           evaluator: RuleBuilders.minimumBitrate(50_000_000)),
            // CONTAINER
            ConformityRule(id: "container", title: "Conteneur", severity: .recommended,
                           expectedHumanReadable: "MXF (OP1a) ou MOV",
                           explanation: "MXF = standard SMPTE broadcast. MOV pour livraison ProRes.",
                           evaluator: RuleBuilders.containerExtensionIn(["mxf", "mov"]))
        ]
    )

    // MARK: DCP cinéma
    static let dcpFeature = ConformityPreset(
        id: "dcp.feature",
        name: "DCP Cinéma (DCI)",
        summary: "Digital Cinema Package — JPEG2000, 24 fps, 48 kHz/24-bit/5.1+, Rec.709 ou DCI-P3.",
        rules: [
            ConformityRule(id: "v.codec", title: "Codec vidéo", severity: .mandatory,
                           expectedHumanReadable: "JPEG 2000",
                           explanation: "Le DCP exige le codec JPEG 2000 (j2k).",
                           evaluator: RuleBuilders.videoCodec(in: ["JPEG 2000", "j2k", "JPEG2000"])),
            ConformityRule(id: "v.fps", title: "FPS", severity: .mandatory,
                           expectedHumanReadable: "24 ou 48 fps",
                           explanation: "DCI standard : 24 fps cinéma (HFR : 48).",
                           evaluator: RuleBuilders.fpsIn([24, 48])),
            ConformityRule(id: "v.res", title: "Résolution", severity: .recommended,
                           expectedHumanReadable: "2048×1080 (2K) ou 4096×2160 (4K)",
                           explanation: "Résolutions DCI 2K ou 4K.",
                           evaluator: RuleBuilders.minResolution(width: 2048, height: 1080)),
            ConformityRule(id: "v.bd", title: "Profondeur", severity: .mandatory,
                           expectedHumanReadable: "≥ 12 bits",
                           explanation: "DCP nécessite 12 bits XYZ.",
                           evaluator: RuleBuilders.minBitDepth(12)),
            ConformityRule(id: "a.sr", title: "Audio sample rate", severity: .mandatory,
                           expectedHumanReadable: "48 ou 96 kHz",
                           explanation: "Sample rate DCI.",
                           evaluator: RuleBuilders.minSampleRate(48000)),
            ConformityRule(id: "a.ch", title: "Canaux audio", severity: .recommended,
                           expectedHumanReadable: "≥ 5.1 (6 canaux)",
                           explanation: "Surround minimum pour la salle.",
                           evaluator: RuleBuilders.minChannels(6))
        ]
    )

    // MARK: YouTube 4K
    static let youtube4K = ConformityPreset(
        id: "youtube.4k",
        name: "YouTube 4K",
        summary: "Recommandations YouTube pour upload 4K (H.264 ou HEVC, 48 kHz audio).",
        rules: [
            ConformityRule(id: "v.codec", title: "Codec", severity: .recommended,
                           expectedHumanReadable: "H.264 High ou HEVC",
                           explanation: "Codecs supportés par YouTube pour 4K.",
                           evaluator: RuleBuilders.videoCodec(in: ["AVC", "H.264", "HEVC", "H.265"])),
            ConformityRule(id: "v.res", title: "Résolution", severity: .recommended,
                           expectedHumanReadable: "≥ 3840×2160",
                           explanation: "4K UHD minimum pour profiter du label 4K YouTube.",
                           evaluator: RuleBuilders.minResolution(width: 3840, height: 2160)),
            ConformityRule(id: "v.fps", title: "FPS", severity: .informational,
                           expectedHumanReadable: "24/25/30/48/50/60",
                           explanation: "Cadences supportées par YouTube.",
                           evaluator: RuleBuilders.fpsIn([23.976, 24, 25, 29.97, 30, 48, 50, 59.94, 60])),
            ConformityRule(id: "a.sr", title: "Fréquence audio", severity: .mandatory,
                           expectedHumanReadable: "≥ 48 kHz",
                           explanation: "48 kHz pour qualité optimale.",
                           evaluator: RuleBuilders.minSampleRate(48000)),
            ConformityRule(id: "a.lufs", title: "Loudness", severity: .informational,
                           expectedHumanReadable: "−14 LUFS (cible YouTube)",
                           explanation: "YouTube normalise à −14 LUFS. En-dessous = perte de loudness à l'upload.",
                           evaluator: RuleBuilders.lufsInRange(low: -16, high: -12))
        ]
    )

    // MARK: ProRes 422 HQ Delivery
    static let proResHQDelivery = ConformityPreset(
        id: "prores.422hq",
        name: "ProRes 422 HQ Delivery",
        summary: "Master pro édité : Apple ProRes 422 HQ, 10 bits, 4:2:2, audio 48 kHz/24-bit.",
        rules: [
            ConformityRule(id: "v.codec", title: "Codec", severity: .mandatory,
                           expectedHumanReadable: "Apple ProRes 422 HQ",
                           explanation: "Le master demande ProRes 422 HQ. Autres ProRes acceptés selon contrat.",
                           evaluator: RuleBuilders.videoCodec(in: ["ProRes 422 HQ", "ProRes 4444", "ProRes 422"])),
            ConformityRule(id: "v.bd", title: "Profondeur", severity: .mandatory,
                           expectedHumanReadable: "≥ 10 bits",
                           explanation: "ProRes 422 HQ natif = 10 bits.",
                           evaluator: RuleBuilders.minBitDepth(10)),
            ConformityRule(id: "v.chroma", title: "Chroma", severity: .mandatory,
                           expectedHumanReadable: "4:2:2 ou 4:4:4",
                           explanation: "Pas de 4:2:0 sur master pro.",
                           evaluator: RuleBuilders.chromaSubsamplingIn(["4:2:2", "4:4:4", "4:4:4:4"])),
            ConformityRule(id: "a.sr", title: "Sample rate", severity: .mandatory,
                           expectedHumanReadable: "48 kHz",
                           explanation: "Standard pro.",
                           evaluator: RuleBuilders.minSampleRate(48000))
        ]
    )

    // MARK: Web HTML5 generic
    static let webHTML5 = ConformityPreset(
        id: "web.html5",
        name: "Web HTML5",
        summary: "Compatibilité large navigateur : H.264 baseline/main, AAC 48 kHz stereo, MP4.",
        rules: [
            ConformityRule(id: "v.codec", title: "Codec vidéo", severity: .mandatory,
                           expectedHumanReadable: "H.264 (AVC)",
                           explanation: "Codec universellement supporté sur le Web.",
                           evaluator: RuleBuilders.videoCodec(in: ["AVC", "H.264"])),
            ConformityRule(id: "v.bd", title: "Profondeur", severity: .mandatory,
                           expectedHumanReadable: "8 bits",
                           explanation: "10 bits H.264 = lecture limitée sur Safari/Chrome iOS.",
                           evaluator: { a in
                               guard let v = a.videoTracks.first, let d = v.bitDepth else { return (.notApplicable, "—") }
                               return (d <= 8 ? .pass : .warning, "\(d) bits")
                           }),
            ConformityRule(id: "a.codec", title: "Codec audio", severity: .mandatory,
                           expectedHumanReadable: "AAC LC",
                           explanation: "AAC = codec universel HTML5.",
                           evaluator: RuleBuilders.audioCodec(in: ["AAC"])),
            ConformityRule(id: "a.sr", title: "Sample rate", severity: .recommended,
                           expectedHumanReadable: "44.1 ou 48 kHz",
                           explanation: "Standard Web.",
                           evaluator: RuleBuilders.minSampleRate(44100)),
            ConformityRule(id: "a.ch", title: "Canaux audio", severity: .recommended,
                           expectedHumanReadable: "≤ 2 (stereo)",
                           explanation: "Surround peu supporté par les navigateurs.",
                           evaluator: { a in
                               guard let ch = a.audioTracks.first?.channelCount else { return (.notApplicable, "—") }
                               return (ch <= 2 ? .pass : .warning, "\(ch)")
                           })
        ]
    )
}

// MARK: - Checker

nonisolated enum ConformityChecker {

    static func evaluate(_ analysis: MediaAnalysis, against preset: ConformityPreset) -> [ConformityResult] {
        preset.rules.map { rule in
            let (status, actual) = rule.evaluator(analysis)
            return ConformityResult(
                ruleID: rule.id,
                ruleTitle: rule.title,
                expected: rule.expectedHumanReadable,
                actual: actual,
                status: status,
                severity: rule.severity,
                explanation: rule.explanation
            )
        }
    }

    /// Score sur 100, calculé sur les règles mandatory + recommended uniquement.
    /// Si TOUTES les règles sont N/A (preset qui exige du contenu absent du fichier),
    /// on retourne 0 et non 100 — sinon un fichier audio-seul contre un preset HDR10
    /// passerait pour 100 % conforme à tort.
    static func score(_ results: [ConformityResult]) -> Double {
        let evaluable = results.filter { $0.severity != .informational }
        let applicable = evaluable.filter { $0.status != .notApplicable }
        // Cas pathologique : aucune règle applicable → preset incompatible avec le média
        if applicable.isEmpty {
            return evaluable.isEmpty ? 100 : 0
        }
        // Les règles non applicables pèsent comme des échecs partiels (pondération 0.5)
        let passing = applicable.filter { $0.status == .pass }.count
        let denominator = applicable.count + (evaluable.count - applicable.count) / 2
        return Double(passing) / Double(max(1, denominator)) * 100
    }

    /// Nombre de mandatory failed.
    static func criticalFailures(_ results: [ConformityResult]) -> Int {
        results.filter { $0.severity == .mandatory && $0.status == .fail }.count
    }
}
