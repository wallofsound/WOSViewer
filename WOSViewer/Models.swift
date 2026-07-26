import Foundation

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

struct AnalysisResult: Identifiable {
    let id = UUID()
    let sourceName: String
    let sourceURL: URL?
    let sampleRate: Double
    let duration: Double
    let hopLength: Int
    let frameLength: Int
    let series: [FeatureSeries]
    let csvURL: URL?
    let score: ScoreDocument
    let scoreURL: URL?

    var title: String {
        "WOS Viewer — Quantitative Analysis of \(sourceName)"
    }
}
