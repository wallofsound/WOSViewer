import Foundation
import CoreGraphics

struct FeaturePoint: Identifiable, Hashable {
    let id: Int
    let time: Double
    let value: Double
}

struct FeatureSeries: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case rms = "RMS Energy (Loudness Profile)"
        case novelty = "Novelty Curve (Onset Strength Function)"
        case centroid = "Spectral Centroid (Brightness)"
        case zcr = "Zero-Crossing Rate (Noisiness/Percussiveness)"
        case mfcc1 = "MFCC₁ (Timbral Texture Cue)"

        var id: String { rawValue }

        var yLabel: String {
            switch self {
            case .rms: return "RMS (Normalized)"
            case .novelty: return "Novelty Value"
            case .centroid: return "Frequency (Hz)"
            case .zcr: return "ZCR"
            case .mfcc1: return "MFCC₁"
            }
        }
    }

    let kind: Kind
    let points: [FeaturePoint]
    var id: String { kind.id }
}

/// Compact log-mel spectrogram for score underlay (not full FFT dump).
struct SpectrogramData {
    /// Time columns (left → right).
    let columnCount: Int
    /// Mel bands (index 0 = lowest frequency).
    let bandCount: Int
    /// Column-major: `magnitudes[column * bandCount + band]`, normalized 0…1.
    let magnitudes: [Float]
    let duration: Double
    let minHz: Double
    let maxHz: Double
    let sampleRate: Double

    /// Builds an RGBA image: low freq at bottom, high at top (matches score lanes).
    func makeCGImage() -> CGImage? {
        guard columnCount > 0, bandCount > 0,
              magnitudes.count >= columnCount * bandCount else { return nil }

        var pixels = [UInt8](repeating: 0, count: columnCount * bandCount * 4)
        for c in 0..<columnCount {
            for b in 0..<bandCount {
                let v = max(0, min(1, magnitudes[c * bandCount + b]))
                // Soft ink: dark teal → warm amber; transparent when quiet.
                let t = Double(v)
                let alphaF = 0.05 + 0.72 * pow(t, 0.65)
                let alpha = UInt8(min(255, Int(alphaF * 255)))
                let rF = 0.12 + 0.78 * t
                let gF = 0.18 + 0.45 * (1 - t) + 0.25 * t
                let bF = 0.28 + 0.35 * (1 - t)
                let y = bandCount - 1 - b
                let idx = (y * columnCount + c) * 4
                pixels[idx] = UInt8(min(255, Int(rF * alphaF * 255)))
                pixels[idx + 1] = UInt8(min(255, Int(gF * alphaF * 255)))
                pixels[idx + 2] = UInt8(min(255, Int(bF * alphaF * 255)))
                pixels[idx + 3] = alpha
            }
        }

        let bytesPerRow = columnCount * 4
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: columnCount,
            height: bandCount,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

struct AnalysisResult: Identifiable {
    let id = UUID()
    let sourceName: String
    let sourceURL: URL?
    let sampleRate: Double
    let duration: Double
    let hopLength: Int
    let frameLength: Int
    let series: [FeatureSeries]
    let spectrogram: SpectrogramData?
    let csvURL: URL?
    let score: ScoreDocument
    let scoreURL: URL?

    var title: String {
        "WOS Viewer — Quantitative Analysis of \(sourceName)"
    }
}
