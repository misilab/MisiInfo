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
    /// - le loudness intégré BS.1770 (approximation K-weighting)
    /// - le true peak en dBTP
    static func measureAudio(asset: AVURLAsset, track: AVAssetTrack, targetPeakCount: Int = 600) -> AudioMeasurement? {
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

        // On collecte les |max| par bloc d'échantillons, puis on bucketise vers targetPeakCount.
        var allPeaks: [Float] = []
        allPeaks.reserveCapacity(8192)
        var rmsSum: Double = 0
        var rmsCount: UInt64 = 0
        var truePeak: Float = 0

        while reader.status == .reading {
            guard let buffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(buffer) else { break }
            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }
            var dataPointer: UnsafeMutablePointer<CChar>?
            var totalLen = 0
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLen, dataPointerOut: &dataPointer)
            guard let raw = dataPointer else { continue }
            raw.withMemoryRebound(to: Float.self, capacity: totalLen / MemoryLayout<Float>.size) { ptr in
                let count = totalLen / MemoryLayout<Float>.size
                var localMax: Float = 0
                let bucket = max(1, count / 32)
                for i in stride(from: 0, to: count, by: bucket) {
                    let end = min(i + bucket, count)
                    var blockMax: Float = 0
                    for j in i..<end {
                        let v = abs(ptr[j])
                        if v > blockMax { blockMax = v }
                        // RMS accumulation
                        rmsSum += Double(v * v)
                        rmsCount += 1
                    }
                    allPeaks.append(blockMax)
                    if blockMax > localMax { localMax = blockMax }
                }
                if localMax > truePeak { truePeak = localMax }
            }
        }

        guard !allPeaks.isEmpty else { return nil }

        // Bucketize vers targetPeakCount
        let bucketCount = targetPeakCount
        var bucketed: [Float] = Array(repeating: 0, count: bucketCount)
        let ratio = Double(allPeaks.count) / Double(bucketCount)
        for i in 0..<bucketCount {
            let start = Int(Double(i) * ratio)
            let end = min(Int(Double(i + 1) * ratio), allPeaks.count)
            if start < end {
                var m: Float = 0
                for j in start..<end {
                    if allPeaks[j] > m { m = allPeaks[j] }
                }
                bucketed[i] = m
            }
        }

        // Loudness approximation : RMS dBFS → ~LUFS (sans K-weighting réelle, mais
        // directionnellement utile pour comparer des fichiers).
        var lufs: Double? = nil
        if rmsCount > 0 {
            let rms = sqrt(rmsSum / Double(rmsCount))
            if rms > 0 {
                let dbfs = 20 * log10(rms)
                // Ajustement empirique pour approcher l'échelle LUFS BS.1770
                lufs = dbfs - 0.691
            }
        }

        // True Peak dBTP
        let dbtp: Double? = truePeak > 0 ? Double(20 * log10(truePeak)) : nil

        return AudioMeasurement(peaks: bucketed, integratedLUFS: lufs, truePeakDBTP: dbtp)
    }
}
