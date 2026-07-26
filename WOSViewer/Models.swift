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

        var id: String { rawValue }

        var yLabel: String {
            switch self {
            case .rms: return "RMS (Normalized)"
            case .novelty: return "Novelty Value"
            case .centroid: return "Frequency (Hz)"
            case .zcr: return "ZCR"
            }
        }

        var colorName: String {
            switch self {
            case .rms: return "rms"
            case .novelty: return "novelty"
            case .centroid: return "centroid"
            case .zcr: return "zcr"
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
    let sampleRate: Double
    let duration: Double
    let hopLength: Int
    let frameLength: Int
    let series: [FeatureSeries]
    let csvURL: URL?

    var title: String {
        "WOS Viewer — Quantitative Analysis of \(sourceName)"
    }
}
