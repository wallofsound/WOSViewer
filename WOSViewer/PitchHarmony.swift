import Foundation
import Accelerate

enum KeyMode: String, Codable {
    case major
    case minor

    var labelSV: String {
        switch self {
        case .major: return "dur"
        case .minor: return "moll"
        }
    }
}

struct PitchAnalysis {
    /// Hz per frame; 0 = unvoiced / indefinite.
    let f0Hz: [Double]
    /// 0…1 periodicity / harmonicity per frame.
    let harmonicity: [Double]
    /// Average chroma (12), C=0 … B=11.
    let meanChroma: [Double]
    let keyRoot: Int
    let keyMode: KeyMode
    let keyConfidence: Double

    var keyLabel: String {
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let root = names[(keyRoot % 12 + 12) % 12]
        return "\(root) \(keyMode.labelSV)"
    }

    static let empty = PitchAnalysis(
        f0Hz: [],
        harmonicity: [],
        meanChroma: Array(repeating: 0, count: 12),
        keyRoot: 0,
        keyMode: .major,
        keyConfidence: 0
    )
}

enum PitchHarmony {
    // Krumhansl-Kessler key profiles
    private static let majorProfile: [Double] = [
        6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88
    ]
    private static let minorProfile: [Double] = [
        6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17
    ]

    static func analyze(
        frames: [[Float]],
        spectra: [[Float]],
        sampleRate: Double,
        fftSize: Int
    ) -> PitchAnalysis {
        precondition(frames.count == spectra.count || spectra.isEmpty || frames.isEmpty)

        var f0 = [Double](repeating: 0, count: frames.count)
        var harm = [Double](repeating: 0, count: frames.count)
        for i in frames.indices {
            let est = estimatePitch(frame: frames[i], sampleRate: sampleRate)
            f0[i] = est.hz
            harm[i] = est.harmonicity
        }

        var chromaAcc = [Double](repeating: 0, count: 12)
        var chromaWeight = 0.0
        for (i, mag) in spectra.enumerated() {
            let c = chromaVector(magnitude: mag, sampleRate: sampleRate, fftSize: fftSize)
            let w = max(0.05, harm.indices.contains(i) ? harm[i] : 0.2)
            for k in 0..<12 {
                chromaAcc[k] += c[k] * w
            }
            chromaWeight += w
        }
        if chromaWeight > 1e-9 {
            for k in 0..<12 { chromaAcc[k] /= chromaWeight }
        }

        let key = detectKey(chroma: chromaAcc)
        return PitchAnalysis(
            f0Hz: f0,
            harmonicity: harm,
            meanChroma: chromaAcc,
            keyRoot: key.root,
            keyMode: key.mode,
            keyConfidence: key.confidence
        )
    }

    /// Autocorrelation pitch + harmonicity in ~65–1000 Hz.
    static func estimatePitch(frame: [Float], sampleRate: Double) -> (hz: Double, harmonicity: Double) {
        let n = frame.count
        guard n > 64 else { return (0, 0) }

        var mean: Float = 0
        vDSP_meanv(frame, 1, &mean, vDSP_Length(n))
        var centered = frame
        var neg = -mean
        vDSP_vsadd(frame, 1, &neg, &centered, 1, vDSP_Length(n))

        var rms: Float = 0
        vDSP_rmsqv(centered, 1, &rms, vDSP_Length(n))
        guard rms > 1e-5 else { return (0, 0) }

        let minLag = max(2, Int(sampleRate / 1000))      // ~1000 Hz
        let maxLag = min(n / 2, Int(sampleRate / 65))    // ~65 Hz
        guard maxLag > minLag + 2 else { return (0, 0) }

        var bestLag = minLag
        var bestCorr: Float = -1
        var energy0: Float = 0
        vDSP_svesq(centered, 1, &energy0, vDSP_Length(n))
        guard energy0 > 1e-10 else { return (0, 0) }

        // Coarse search then refine — keep cost bounded
        let step = max(1, (maxLag - minLag) / 180)
        var lag = minLag
        while lag <= maxLag {
            var corr: Float = 0
            let len = n - lag
            centered.withUnsafeBufferPointer { buf in
                vDSP_dotpr(buf.baseAddress!, 1, buf.baseAddress! + lag, 1, &corr, vDSP_Length(len))
            }
            corr /= energy0
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
            lag += step
        }

        // Local refine
        let lo = max(minLag, bestLag - step)
        let hi = min(maxLag, bestLag + step)
        for l in lo...hi {
            var corr: Float = 0
            let len = n - l
            centered.withUnsafeBufferPointer { buf in
                vDSP_dotpr(buf.baseAddress!, 1, buf.baseAddress! + l, 1, &corr, vDSP_Length(len))
            }
            corr /= energy0
            if corr > bestCorr {
                bestCorr = corr
                bestLag = l
            }
        }

        let harmonicity = Double(max(0, min(1, bestCorr)))
        // Require clear periodicity
        guard harmonicity >= 0.35 else { return (0, harmonicity) }
        let hz = sampleRate / Double(bestLag)
        guard hz >= 65, hz <= 1000 else { return (0, harmonicity) }
        return (hz, harmonicity)
    }

    static func chromaVector(magnitude: [Float], sampleRate: Double, fftSize: Int) -> [Double] {
        var chroma = [Double](repeating: 0, count: 12)
        let binHz = sampleRate / Double(fftSize)
        for i in 1..<magnitude.count {
            let hz = Double(i) * binHz
            guard hz >= 50, hz <= 5000 else { continue }
            let midi = 69.0 + 12.0 * log2(hz / 440.0)
            guard midi.isFinite else { continue }
            var pc = Int(midi.rounded()) % 12
            if pc < 0 { pc += 12 }
            chroma[pc] += Double(magnitude[i])
        }
        let sum = chroma.reduce(0, +)
        if sum > 1e-12 {
            for i in 0..<12 { chroma[i] /= sum }
        }
        return chroma
    }

    static func detectKey(chroma: [Double]) -> (root: Int, mode: KeyMode, confidence: Double) {
        var bestRoot = 0
        var bestMode = KeyMode.major
        var bestScore = -Double.infinity
        var second = -Double.infinity

        for root in 0..<12 {
            let maj = correlation(chroma, rotate(majorProfile, by: root))
            let minr = correlation(chroma, rotate(minorProfile, by: root))
            if maj > bestScore {
                second = bestScore
                bestScore = maj
                bestRoot = root
                bestMode = .major
            } else if maj > second {
                second = maj
            }
            if minr > bestScore {
                second = bestScore
                bestScore = minr
                bestRoot = root
                bestMode = .minor
            } else if minr > second {
                second = minr
            }
        }
        let conf = max(0, min(1, (bestScore - second) * 2.5 + 0.35))
        return (bestRoot, bestMode, conf)
    }

    /// Nashville number for a pitch class relative to key (e.g. "1", "b3", "5").
    static func nashvilleNumber(pitchClass: Int, keyRoot: Int, mode: KeyMode) -> String {
        let deg = ((pitchClass - keyRoot) % 12 + 12) % 12
        // Scale degrees in semitones from tonic
        let majorMap: [Int: String] = [
            0: "1", 1: "b2", 2: "2", 3: "b3", 4: "3", 5: "4",
            6: "#4", 7: "5", 8: "b6", 9: "6", 10: "b7", 11: "7"
        ]
        let minorMap: [Int: String] = [
            0: "1", 1: "b2", 2: "2", 3: "3", 4: "#3", 5: "4",
            6: "#4", 7: "5", 8: "6", 9: "#6", 10: "7", 11: "#7"
        ]
        // Natural minor prefers b3,b6,b7 as diatonic
        let naturalMinor: [Int: String] = [
            0: "1", 1: "b2", 2: "2", 3: "b3", 4: "3", 5: "4",
            6: "#4", 7: "5", 8: "b6", 9: "6", 10: "b7", 11: "7"
        ]
        switch mode {
        case .major: return majorMap[deg] ?? "?"
        case .minor: return naturalMinor[deg] ?? minorMap[deg] ?? "?"
        }
    }

    static func pitchClass(fromHz hz: Double) -> Int? {
        guard hz > 50 else { return nil }
        let midi = 69.0 + 12.0 * log2(hz / 440.0)
        guard midi.isFinite else { return nil }
        var pc = Int(midi.rounded()) % 12
        if pc < 0 { pc += 12 }
        return pc
    }

    static func medianVoicedPitchClass(f0: [Double], times: [Double], start: Double, end: Double) -> Int? {
        guard !f0.isEmpty, f0.count == times.count else { return nil }
        var pcs: [Int] = []
        for i in times.indices {
            let t = times[i]
            guard t >= start, t <= end else { continue }
            if let pc = pitchClass(fromHz: f0[i]) {
                pcs.append(pc)
            }
        }
        guard !pcs.isEmpty else { return nil }
        // Mode (most common pitch class)
        var counts = [Int: Int]()
        for p in pcs { counts[p, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key
    }

    private static func rotate(_ v: [Double], by root: Int) -> [Double] {
        (0..<12).map { v[($0 - root + 12) % 12] }
    }

    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == 12, b.count == 12 else { return 0 }
        let ma = a.reduce(0, +) / 12
        let mb = b.reduce(0, +) / 12
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<12 {
            let x = a[i] - ma
            let y = b[i] - mb
            num += x * y
            da += x * x
            db += y * y
        }
        let den = sqrt(da * db)
        guard den > 1e-12 else { return 0 }
        return num / den
    }
}
