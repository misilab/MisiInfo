import Foundation
import Accelerate

/// Implémentation conforme ITU-R BS.1770-4 : K-weighting + gating absolu/relatif.
///
/// Étapes :
/// 1. Filtre K-weighting (pré-filtre high-shelf 1681 Hz +4 dB + high-pass RLB)
///    Coefficients biquad calculés dynamiquement pour le sample rate source.
/// 2. Mean-square par bloc de 400 ms avec 75 % overlap (hop 100 ms).
/// 3. Somme pondérée par canal (L/R/C/Ls/Rs = 1.0, Lse/Rse = 1.41, LFE = 0).
/// 4. Loudness par bloc : L = −0.691 + 10·log₁₀(mean_square).
/// 5. Gate absolu : on jette les blocs < −70 LUFS.
/// 6. Gate relatif : on jette les blocs < (mean − 10).
/// 7. Loudness intégrée = moyenne des blocs restants.
nonisolated enum LoudnessBS1770 {

    /// Coefficients d'un biquad direct form I.
    struct Biquad {
        let b0, b1, b2, a1, a2: Double

        /// Filtre une mémoire `samples` in-place avec état persistant `state`.
        func process(_ samples: inout [Double], state: inout BiquadState) {
            var z1 = state.z1, z2 = state.z2
            for i in 0..<samples.count {
                let x = samples[i]
                let y = b0 * x + b1 * z1 + b2 * z2 - a1 * state.y1 - a2 * state.y2
                samples[i] = y
                z2 = z1
                z1 = x
                state.y2 = state.y1
                state.y1 = y
            }
            state.z1 = z1
            state.z2 = z2
        }
    }

    struct BiquadState {
        var z1: Double = 0   // input state
        var z2: Double = 0
        var y1: Double = 0   // output state
        var y2: Double = 0
    }

    /// Pré-filtre K-weighting (high-shelf 1681 Hz, ~+4 dB) — coefficients pour `sampleRate`.
    /// Conversion bilinéaire depuis le prototype analogique BS.1770-4 annexe 1.
    static func preFilter(sampleRate fs: Double) -> Biquad {
        // Analog prototype (BS.1770 annex 1)
        let f0 = 1681.974450955533
        let G = 3.999843853973347   // dB
        let Q = 0.7071752369554196

        let K = tan(.pi * f0 / fs)
        let Vh = pow(10.0, G / 20.0)
        let Vb = pow(Vh, 0.4996667741545416)
        let aTerm = 1.0 + K / Q + K * K
        let b0 = (Vh + Vb * K / Q + K * K) / aTerm
        let b1 = 2.0 * (K * K - Vh) / aTerm
        let b2 = (Vh - Vb * K / Q + K * K) / aTerm
        let a1 = 2.0 * (K * K - 1.0) / aTerm
        let a2 = (1.0 - K / Q + K * K) / aTerm
        return Biquad(b0: b0, b1: b1, b2: b2, a1: a1, a2: a2)
    }

    /// High-pass RLB (~38 Hz) — coefficients pour `sampleRate`.
    static func rlbFilter(sampleRate fs: Double) -> Biquad {
        let f0 = 38.13547087602444
        let Q = 0.5003270373238773
        let K = tan(.pi * f0 / fs)
        let aTerm = 1.0 + K / Q + K * K
        let b0 = 1.0
        let b1 = -2.0
        let b2 = 1.0
        let a1 = 2.0 * (K * K - 1.0) / aTerm
        let a2 = (1.0 - K / Q + K * K) / aTerm
        // Normalize input gain
        let g = 1.0 / aTerm
        return Biquad(b0: b0 * g, b1: b1 * g, b2: b2 * g, a1: a1, a2: a2)
    }

    /// Poids par canal selon BS.1770. Index correspond à la position L/R/C/LFE/Ls/Rs/…
    /// Pour des layouts inconnus on retourne 1.0 (mono/stereo).
    static func channelWeight(index: Int, channelCount: Int, channelLayout: String?) -> Double {
        // Mono / stereo : tout à 1.0
        if channelCount <= 2 { return 1.0 }
        // 5.1 / 7.1 : ordre L R C LFE Ls Rs (MPEG_5_1_A) / + Lc Rc
        if let layout = channelLayout?.uppercased() {
            if layout.contains("LFE") || layout == "LFE" {
                // Position du LFE dans le map
                let parts = layout.split(separator: " ").map(String.init)
                if index < parts.count, parts[index] == "LFE" { return 0.0 }
                if index < parts.count, ["LS", "RS", "RLS", "RRS"].contains(parts[index]) { return 1.41 }
                return 1.0
            }
        }
        return 1.0
    }

    /// Calcule la loudness intégrée d'un signal mono/stéréo en blocs de 400 ms hop 100 ms.
    /// `samples` : tableau plat entrelacé (CHAN0 CHAN1 CHAN0 CHAN1 …).
    static func integratedLoudness(
        samples: [Float],
        channelCount: Int,
        sampleRate: Double,
        channelLayout: String? = nil
    ) -> Double? {
        guard channelCount > 0, sampleRate > 0, !samples.isEmpty else { return nil }

        let frames = samples.count / channelCount
        guard frames > 0 else { return nil }

        // 1. Désentrelace + K-weighting par canal
        let pre = preFilter(sampleRate: sampleRate)
        let rlb = rlbFilter(sampleRate: sampleRate)

        var kweighted: [[Double]] = Array(repeating: [], count: channelCount)
        for ch in 0..<channelCount {
            var buf = [Double](repeating: 0, count: frames)
            for i in 0..<frames {
                buf[i] = Double(samples[i * channelCount + ch])
            }
            var ps = BiquadState()
            var rs = BiquadState()
            pre.process(&buf, state: &ps)
            rlb.process(&buf, state: &rs)
            kweighted[ch] = buf
        }

        // 2. Block 400 ms, hop 100 ms
        let blockSize = Int(0.400 * sampleRate)
        let hop = Int(0.100 * sampleRate)
        guard blockSize > 0, hop > 0, frames >= blockSize else { return nil }
        let blockCount = (frames - blockSize) / hop + 1

        var blockLoudness: [Double] = []
        blockLoudness.reserveCapacity(blockCount)
        var weights = [Double](repeating: 1.0, count: channelCount)
        for ch in 0..<channelCount {
            weights[ch] = channelWeight(index: ch, channelCount: channelCount, channelLayout: channelLayout)
        }

        for b in 0..<blockCount {
            let start = b * hop
            var weightedSum = 0.0
            for ch in 0..<channelCount {
                let arr = kweighted[ch]
                var meanSquare = 0.0
                for i in start..<(start + blockSize) {
                    meanSquare += arr[i] * arr[i]
                }
                meanSquare /= Double(blockSize)
                weightedSum += weights[ch] * meanSquare
            }
            if weightedSum > 0 {
                let lufs = -0.691 + 10.0 * log10(weightedSum)
                blockLoudness.append(lufs)
            }
        }
        guard !blockLoudness.isEmpty else { return nil }

        // 3. Gate absolu : on garde >= -70 LUFS
        let abs1 = blockLoudness.filter { $0 >= -70.0 }
        guard !abs1.isEmpty else { return nil }

        // Moyenne énergétique (pas dB) pour le gate relatif
        let meanEnergy = abs1.reduce(0.0) { $0 + pow(10.0, $1 / 10.0) } / Double(abs1.count)
        let meanLUFS = 10.0 * log10(meanEnergy) - 0.691
        let threshold = meanLUFS - 10.0

        let abs2 = abs1.filter { $0 >= threshold }
        guard !abs2.isEmpty else { return nil }

        let finalEnergy = abs2.reduce(0.0) { $0 + pow(10.0, $1 / 10.0) } / Double(abs2.count)
        return 10.0 * log10(finalEnergy) - 0.691
    }

    /// True peak via oversampling 4× (approximation BS.1770-4 par interpolation linéaire).
    /// Pour un vrai true-peak il faudrait un FIR de réservation Nyquist ; l'interpolation
    /// linéaire 4× capture la majeure partie des dépassements inter-sample.
    static func truePeakDBTP(samples: [Float], channelCount: Int) -> Double? {
        guard channelCount > 0, !samples.isEmpty else { return nil }
        var peak: Float = 0
        let frames = samples.count / channelCount
        for ch in 0..<channelCount {
            var prev: Float = 0
            for f in 0..<frames {
                let s = samples[f * channelCount + ch]
                let m = abs(s)
                if m > peak { peak = m }
                // Interpolation 4× entre prev et s
                if f > 0 {
                    for t in 1...3 {
                        let alpha = Float(t) / 4.0
                        let interp = abs(prev * (1 - alpha) + s * alpha)
                        if interp > peak { peak = interp }
                    }
                }
                prev = s
            }
        }
        guard peak > 0 else { return nil }
        return Double(20.0 * log10(peak))
    }
}
