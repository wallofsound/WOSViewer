import SwiftUI

/// Malinowski-style harmonic coloring: pitch classes around the circle of fifths.
/// Blue = tonic (I); blue→red = motion toward the dominant (V).
enum HarmonicColoring {
    /// Circle-of-fifths index for pitch class C=0 … B=11 (C→G→D→…).
    static func fifthsIndex(pitchClass: Int) -> Int {
        let table = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
        return table[(pitchClass % 12 + 12) % 12]
    }

    /// Steps along the circle of fifths from tonic toward the dominant (0…11).
    static func fifthsFromTonic(pitchClass: Int, keyRoot: Int) -> Int {
        let a = fifthsIndex(pitchClass: pitchClass)
        let b = fifthsIndex(pitchClass: keyRoot)
        return (a - b + 12) % 12
    }

    /// Color for a pitch class relative to key tonic.
    static func color(pitchClass: Int, keyRoot: Int, saturation: Double = 0.72, brightness: Double = 0.78) -> Color {
        let rgb = rgbComponents(pitchClass: pitchClass, keyRoot: keyRoot, saturation: saturation, brightness: brightness)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static func hex(pitchClass: Int, keyRoot: Int, saturation: Double = 0.72, brightness: Double = 0.78) -> String {
        let rgb = rgbComponents(pitchClass: pitchClass, keyRoot: keyRoot, saturation: saturation, brightness: brightness)
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.r * 255).rounded()),
            Int((rgb.g * 255).rounded()),
            Int((rgb.b * 255).rounded())
        )
    }

    private static func rgbComponents(
        pitchClass: Int,
        keyRoot: Int,
        saturation: Double,
        brightness: Double
    ) -> (r: Double, g: Double, b: Double) {
        let step = fifthsFromTonic(pitchClass: pitchClass, keyRoot: keyRoot)
        var hue = (210.0 - Double(step) * 30.0) / 360.0
        hue -= floor(hue)
        return hsbToRGB(h: hue, s: saturation, b: brightness)
    }

    private static func hsbToRGB(h: Double, s: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = b * (1 - s)
        let q = b * (1 - f * s)
        let t = b * (1 - (1 - f) * s)
        switch i {
        case 0: return (b, t, p)
        case 1: return (q, b, p)
        case 2: return (p, b, t)
        case 3: return (p, q, b)
        case 4: return (t, p, b)
        default: return (b, p, q)
        }
    }

    static func color(fromHz hz: Double, keyRoot: Int, harmonicity: Double = 1) -> Color? {
        guard hz > 50, let pc = PitchHarmony.pitchClass(fromHz: hz) else { return nil }
        let sat = 0.35 + 0.50 * min(1, max(0, harmonicity))
        return color(pitchClass: pc, keyRoot: keyRoot, saturation: sat, brightness: 0.75)
    }

    /// Legend colors for UI (tonic … around the circle toward V).
    static func legendColors(keyRoot: Int) -> [(step: Int, color: Color)] {
        let table = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
        var inverse = [Int](repeating: 0, count: 12)
        for pc in 0..<12 { inverse[table[pc]] = pc }
        let tonicFifths = table[(keyRoot % 12 + 12) % 12]
        return (0..<12).map { step in
            let pc = inverse[(tonicFifths + step) % 12]
            return (step, color(pitchClass: pc, keyRoot: keyRoot))
        }
    }
}

/// Compact F₀ series for pitch-bar rendering.
struct PitchBarsData {
    let times: [Double]
    let f0Hz: [Double]
    let harmonicity: [Double]
    let keyRoot: Int
    let duration: Double

    static func from(pitch: PitchAnalysis, times: [Double]) -> PitchBarsData? {
        guard !pitch.f0Hz.isEmpty, pitch.f0Hz.count == times.count else { return nil }
        return PitchBarsData(
            times: times,
            f0Hz: pitch.f0Hz,
            harmonicity: pitch.harmonicity,
            keyRoot: pitch.keyRoot,
            duration: max(times.last ?? 0, 0.1)
        )
    }
}

/// MAM-inspired pitch plane shape (Bars ≈ piano-roll, Balls ≈ note spheres).
enum PitchRendererStyle: String, CaseIterable, Identifiable {
    case bars
    case balls

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bars: return "Bars"
        case .balls: return "Balls"
        }
    }
}
