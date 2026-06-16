import Foundation
import AVFoundation
import CoreImage
import AppKit

/// Extracteur de prévisualisations : vignette vidéo, waveform audio, mesure de loudness.
/// Toutes les méthodes sont synchrones et destinées à tourner sur un Task.detached background.
nonisolated enum PreviewExtractor {

    // MARK: - Thumbnail vidéo

    /// Extrait une vignette PNG (max ~320px côté long) à mi-fichier.
    static func extractPosterFrame(asset: AVURLAsset, at time: CMTime = .zero) -> Data? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        // Position : 1 seconde dans la vidéo si possible, sinon 0
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

    // MARK: - Audio waveform + loudness

    struct AudioMeasurement {
        let peaks: [Float]           // 0..1 par fenêtre
        let integratedLUFS: Double?  // approximation BS.1770
        let truePeakDBTP: Double?    // dBTP approximé
    }

    /// Lit le PCM de la piste audio et calcule :
    /// - les crêtes pour le waveform
    /// - le loudness intégré BS.1770-4 (K-weighting + gating absolu/relatif)
    /// - le true peak en dBTP (interpolation 4×)
    static func measureAudio(
        asset: AVURLAsset,
        track: AVAssetTrack,
        targetPeakCount: Int = 600
    ) -> AudioMeasurement? {
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

        // Récupère le sample rate + channel count depuis le format description de la piste
        var sampleRate: Double = 48000
        var channelCount: Int = 2
        if let fmt = (CMSampleBufferGetFormatDescription(output.copyNextSampleBuffer() ?? CMSampleBuffer.dummy)) {
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee {
                sampleRate = asbd.mSampleRate
                channelCount = Int(asbd.mChannelsPerFrame)
            }
        }
        // On a peut-être déjà consommé un sample : on recrée le reader pour repartir à zéro
        reader.cancelReading()
        guard let reader2 = try? AVAssetReader(asset: asset) else { return nil }
        let output2 = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output2.alwaysCopiesSampleData = false
        guard reader2.canAdd(output2) else { return nil }
        reader2.add(output2)
        guard reader2.startReading() else { return nil }
        defer { reader2.cancelReading() }

        // Stockage complet des samples Float pour le calcul BS.1770
        var allSamples: [Float] = []
        allSamples.reserveCapacity(Int(sampleRate * 30) * channelCount)
        var allPeaks: [Float] = []
        allPeaks.reserveCapacity(8192)

        while reader2.status == .reading {
            guard let buffer = output2.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { break }
            var dataPointer: UnsafeMutablePointer<CChar>?
            var totalLen = 0
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLen, dataPointerOut: &dataPointer)
            guard let raw = dataPointer, totalLen > 0 else { continue }
            raw.withMemoryRebound(to: Float.self, capacity: totalLen / MemoryLayout<Float>.size) { ptr in
                let count = totalLen / MemoryLayout<Float>.size
                allSamples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
                // Crêtes pour waveform
                let bucket = max(1, count / 32)
                for i in stride(from: 0, to: count, by: bucket) {
                    let end = min(i + bucket, count)
                    var blockMax: Float = 0
                    for j in i..<end {
                        let v = abs(ptr[j])
                        if v > blockMax { blockMax = v }
                    }
                    allPeaks.append(blockMax)
                }
            }
        }
        guard !allSamples.isEmpty, !allPeaks.isEmpty else { return nil }

        // Bucketize pour waveform
        let bucketCount = targetPeakCount
        var bucketed = Array(repeating: Float(0), count: bucketCount)
        let ratio = Double(allPeaks.count) / Double(bucketCount)
        for i in 0..<bucketCount {
            let start = Int(Double(i) * ratio)
            let end = min(Int(Double(i + 1) * ratio), allPeaks.count)
            var m: Float = 0
            for j in start..<end { if allPeaks[j] > m { m = allPeaks[j] } }
            bucketed[i] = m
        }

        // LUFS BS.1770-4
        let lufs = LoudnessBS1770.integratedLoudness(
            samples: allSamples,
            channelCount: channelCount,
            sampleRate: sampleRate,
            channelLayout: nil
        )
        let truePeak = LoudnessBS1770.truePeakDBTP(samples: allSamples, channelCount: channelCount)

        return AudioMeasurement(peaks: bucketed, integratedLUFS: lufs, truePeakDBTP: truePeak)
    }
}

// CMSampleBuffer dummy utility pour éviter une boucle infinie si pas de buffer
extension CMSampleBuffer {
    static var dummy: CMSampleBuffer {
        var sb: CMSampleBuffer!
        CMSampleBufferCreate(allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: nil, sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sb)
        return sb
    }
}
