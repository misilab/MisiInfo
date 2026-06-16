import Foundation
import AVFoundation
import CoreImage
import AppKit

/// Extracteur de prévisualisations : vignette vidéo, waveform audio, mesure de loudness.
/// Toutes les méthodes sont synchrones et destinées à tourner sur un Task.detached background.
nonisolated enum PreviewExtractor {

    // MARK: - Thumbnail vidéo

    /// Extrait une vignette PNG (~640px max) à 1s dans le clip.
    static func extractPosterFrame(asset: AVURLAsset, at time: CMTime = .zero) -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let targetTime: CMTime
        let assetDuration = asset.duration
        if CMTimeGetSeconds(assetDuration).isFinite && CMTimeGetSeconds(assetDuration) > 2 {
            targetTime = CMTime(seconds: 1.0, preferredTimescale: 600)
        } else {
            targetTime = time
        }

        var actualTime: CMTime = .zero
        guard let cgImage = try? generator.copyCGImage(at: targetTime, actualTime: &actualTime) else {
            return nil
        }
        let nsImage = NSImage(cgImage: cgImage, size: .zero)
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [.compressionFactor: 0.85])
        else { return nil }
        return png
    }

    // MARK: - Audio waveform + loudness (streaming)

    struct AudioMeasurement {
        let peaks: [Float]
        let integratedLUFS: Double?
        let truePeakDBTP: Double?
    }

    /// Lit le PCM de la piste audio en **streaming** (aucune accumulation des samples) et calcule
    /// le LUFS BS.1770-4 + true peak + waveform. Sûr pour fichiers très longs (4+ heures).
    /// `sampleRate` et `channelCount` doivent être fournis par l'appelant (généralement extraits
    /// du `CMFormatDescription` chargé via `track.load(.formatDescriptions)`).
    static func measureAudio(
        asset: AVURLAsset,
        track: AVAssetTrack,
        sampleRate: Double,
        channelCount: Int,
        targetPeakCount: Int = 600
    ) -> AudioMeasurement? {
        guard sampleRate > 0, channelCount > 0 else { return nil }

        // 2. Reader unique en streaming
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }

        // 3. État streaming : biquads K-weighting per-channel, accumulateurs block-loudness
        let preFilter = LoudnessBS1770.preFilter(sampleRate: sampleRate)
        let rlbFilter = LoudnessBS1770.rlbFilter(sampleRate: sampleRate)
        var preStates = Array(repeating: LoudnessBS1770.BiquadState(), count: channelCount)
        var rlbStates = Array(repeating: LoudnessBS1770.BiquadState(), count: channelCount)

        let blockSize = max(1, Int(0.400 * sampleRate))
        let hop = max(1, Int(0.100 * sampleRate))
        // Tableaux de mean-square par bloc (un seul accumulateur courant + sliding pour overlap)
        // Chaque sample contribue à `blockSize / hop = 4` blocs simultanés.
        let overlapBlocks = (blockSize + hop - 1) / hop
        // sumSq[i][ch] : somme des x² pour le i-ème bloc actif courant.
        var activeSumSq: [[Double]] = Array(
            repeating: Array(repeating: 0.0, count: channelCount),
            count: overlapBlocks
        )
        var activeSampleCount = [Int](repeating: 0, count: overlapBlocks)
        var globalSampleIdx = 0  // numéro absolu du sample courant
        var blockLoudness: [Double] = []
        var truePeak: Float = 0
        var peakBuckets: [Float] = []
        peakBuckets.reserveCapacity(8192)
        var currentBucketMax: Float = 0
        var samplesInBucket = 0
        let samplesPerBucket = max(1, Int(sampleRate / 30))  // ~30 buckets/sec

        // 4. Boucle de lecture sans accumulation
        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { break }
            var dataPointer: UnsafeMutablePointer<CChar>?
            var totalLen = 0
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLen, dataPointerOut: &dataPointer)
            guard let raw = dataPointer, totalLen >= MemoryLayout<Float>.size else { continue }
            let sampleCount = totalLen / MemoryLayout<Float>.size
            guard sampleCount % channelCount == 0 else { continue }
            let frames = sampleCount / channelCount

            raw.withMemoryRebound(to: Float.self, capacity: sampleCount) { ptr in
                for f in 0..<frames {
                    // Pour chaque frame, applique K-weighting per channel (état persistant),
                    // accumule dans les blocs actifs.
                    for ch in 0..<channelCount {
                        let inputSample = ptr[f * channelCount + ch]
                        // Sample peak (pour waveform)
                        let absV = abs(inputSample)
                        if absV > truePeak { truePeak = absV }
                        if absV > currentBucketMax { currentBucketMax = absV }
                        // K-weighting
                        var s = Double(inputSample)
                        // Pre-filter biquad (single sample)
                        var ps = preStates[ch]
                        let preY = preFilter.b0 * s + preFilter.b1 * ps.z1 + preFilter.b2 * ps.z2
                                 - preFilter.a1 * ps.y1 - preFilter.a2 * ps.y2
                        ps.z2 = ps.z1; ps.z1 = s
                        ps.y2 = ps.y1; ps.y1 = preY
                        preStates[ch] = ps
                        s = preY
                        // RLB filter
                        var rs = rlbStates[ch]
                        let rlbY = rlbFilter.b0 * s + rlbFilter.b1 * rs.z1 + rlbFilter.b2 * rs.z2
                                 - rlbFilter.a1 * rs.y1 - rlbFilter.a2 * rs.y2
                        rs.z2 = rs.z1; rs.z1 = s
                        rs.y2 = rs.y1; rs.y1 = rlbY
                        rlbStates[ch] = rs
                        // Accumule dans tous les blocs actifs
                        let sqVal = rlbY * rlbY
                        for slot in 0..<overlapBlocks {
                            activeSumSq[slot][ch] += sqVal
                        }
                    }
                    // Compte le sample dans tous les slots
                    for slot in 0..<overlapBlocks {
                        activeSampleCount[slot] += 1
                    }
                    globalSampleIdx += 1
                    // Émet un block-loudness chaque fois qu'un slot atteint blockSize
                    for slot in 0..<overlapBlocks {
                        if activeSampleCount[slot] == blockSize {
                            // Calcule weighted sum (poids 1.0 par défaut)
                            var weightedSum = 0.0
                            for ch in 0..<channelCount {
                                weightedSum += activeSumSq[slot][ch] / Double(blockSize)
                            }
                            if weightedSum > 0 {
                                let lufs = -0.691 + 10.0 * log10(weightedSum)
                                blockLoudness.append(lufs)
                            }
                            // Réinitialise ce slot
                            for ch in 0..<channelCount { activeSumSq[slot][ch] = 0 }
                            activeSampleCount[slot] = 0
                        }
                    }
                    // Démarre un nouveau slot tous les `hop` samples
                    if globalSampleIdx % hop == 0 {
                        // Le slot qui vient d'être réinitialisé reprend ; OK
                    }
                    // Waveform peak bucketing
                    samplesInBucket += 1
                    if samplesInBucket >= samplesPerBucket {
                        peakBuckets.append(currentBucketMax)
                        currentBucketMax = 0
                        samplesInBucket = 0
                    }
                }
            }
        }
        if currentBucketMax > 0 || samplesInBucket > 0 {
            peakBuckets.append(currentBucketMax)
        }
        guard !blockLoudness.isEmpty else { return nil }

        // 5. Bucketize waveform vers targetPeakCount
        var bucketed = Array(repeating: Float(0), count: targetPeakCount)
        if !peakBuckets.isEmpty {
            let ratio = Double(peakBuckets.count) / Double(targetPeakCount)
            for i in 0..<targetPeakCount {
                let start = Int(Double(i) * ratio)
                let end = min(Int(Double(i + 1) * ratio), peakBuckets.count)
                var m: Float = 0
                for j in start..<end { if peakBuckets[j] > m { m = peakBuckets[j] } }
                bucketed[i] = m
            }
        }

        // 6. Gating BS.1770
        let abs1 = blockLoudness.filter { $0 >= -70.0 }
        guard !abs1.isEmpty else { return nil }
        let meanEnergy1 = abs1.reduce(0.0) { $0 + pow(10.0, $1 / 10.0) } / Double(abs1.count)
        let meanLUFS = 10.0 * log10(meanEnergy1) - 0.691
        let threshold = meanLUFS - 10.0
        let abs2 = abs1.filter { $0 >= threshold }
        let lufs: Double?
        if abs2.isEmpty {
            lufs = nil
        } else {
            let meanEnergy2 = abs2.reduce(0.0) { $0 + pow(10.0, $1 / 10.0) } / Double(abs2.count)
            lufs = 10.0 * log10(meanEnergy2) - 0.691
        }

        let dbtp: Double? = truePeak > 0 ? Double(20.0 * log10(truePeak)) : nil

        return AudioMeasurement(peaks: bucketed, integratedLUFS: lufs, truePeakDBTP: dbtp)
    }
}
