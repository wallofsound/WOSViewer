import Foundation
import AVFoundation
import Accelerate

enum AnalysisError: LocalizedError {
    case unsupportedFormat
    case emptyAudio
    case readFailed(String)
    case csvMissingColumns([String])

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Kunde inte läsa ljudfilen. Prova wav, mp3 eller m4a."
        case .emptyAudio:
            return "Ljudfilen innehåller ingen data."
        case .readFailed(let message):
            return message
        case .csvMissingColumns(let cols):
            return "CSV saknar kolumner: \(cols.joined(separator: ", "))"
        }
    }
}

/// Feature extraction inspired by SEMA / librosa defaults (22.05 kHz, 2048/512).
struct AudioAnalyzer {
    var targetSampleRate: Double = 22_050
    var frameLength: Int = 2_048
    var hopLength: Int = 512

    func analyzeAudio(at url: URL) throws -> AnalysisResult {
        let mono = try loadMono(url: url, targetSampleRate: targetSampleRate)
        guard !mono.samples.isEmpty else { throw AnalysisError.emptyAudio }

        let frames = frameSignal(mono.samples, frameLength: frameLength, hopLength: hopLength)
        guard !frames.isEmpty else { throw AnalysisError.emptyAudio }

        let rms = frames.map(Self.rms)
        let zcr = frames.map(Self.zeroCrossingRate)
        let spectra = frames.map { Self.magnitudeSpectrum($0, fftSize: frameLength) }
        let centroid = spectra.map {
            Self.spectralCentroid(magnitude: $0, sampleRate: mono.sampleRate, fftSize: frameLength)
        }
        let novelty = Self.spectralFluxNovelty(spectra)
        let mfcc1 = spectra.map {
            Self.mfccFirst(
                magnitude: $0,
                sampleRate: mono.sampleRate,
                fftSize: frameLength
            )
        }

        let times = (0..<frames.count).map {
            Double($0 * hopLength) / mono.sampleRate
        }
        let duration = Double(mono.samples.count) / mono.sampleRate

        let series: [FeatureSeries] = [
            makeSeries(.rms, times: times, values: rms),
            makeSeries(.novelty, times: times, values: novelty),
            makeSeries(.centroid, times: times, values: centroid),
            makeSeries(.zcr, times: times, values: zcr),
            makeSeries(.mfcc1, times: times, values: mfcc1)
        ]

        let csvURL = try? writeCSV(
            beside: url,
            times: times,
            rms: rms,
            centroid: centroid,
            zcr: zcr,
            novelty: novelty,
            mfcc1: mfcc1
        )

        let score: ScoreDocument
        let scoreURL: URL?
        if let existing = ScoreStore.load(beside: url) {
            score = existing
            scoreURL = ScoreStore.url(beside: url)
        } else {
            let built = ScoreBuilder.build(
                sourceName: url.lastPathComponent,
                duration: duration,
                times: times,
                rms: rms,
                centroid: centroid,
                zcr: zcr,
                novelty: novelty
            )
            score = built
            scoreURL = try? ScoreStore.save(built, beside: url)
        }

        return AnalysisResult(
            sourceName: url.lastPathComponent,
            sourceURL: url,
            sampleRate: mono.sampleRate,
            duration: duration,
            hopLength: hopLength,
            frameLength: frameLength,
            series: series,
            csvURL: csvURL,
            score: score,
            scoreURL: scoreURL
        )
    }

    func analyzeCSV(at url: URL) throws -> AnalysisResult {
        let text = try String(contentsOf: url, encoding: .utf8)
        let rows = text.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerLine = rows.first else { throw AnalysisError.emptyAudio }

        let headers = splitCSVLine(headerLine).map { $0.trimmingCharacters(in: .whitespaces) }
        let required = ["Time_Seconds", "RMS_Energy", "Spectral_Centroid", "ZCR", "Novelty_Curve"]
        let missing = required.filter { !headers.contains($0) }
        guard missing.isEmpty else { throw AnalysisError.csvMissingColumns(missing) }

        func index(_ name: String) -> Int { headers.firstIndex(of: name)! }
        let hasMFCC = headers.contains("MFCC_1")

        var times: [Double] = []
        var rms: [Double] = []
        var centroid: [Double] = []
        var zcr: [Double] = []
        var novelty: [Double] = []
        var mfcc1: [Double] = []

        for row in rows.dropFirst() where !row.trimmingCharacters(in: .whitespaces).isEmpty {
            let cols = splitCSVLine(row)
            guard cols.count >= headers.count else { continue }
            times.append(Double(cols[index("Time_Seconds")]) ?? 0)
            rms.append(Double(cols[index("RMS_Energy")]) ?? 0)
            centroid.append(Double(cols[index("Spectral_Centroid")]) ?? 0)
            zcr.append(Double(cols[index("ZCR")]) ?? 0)
            novelty.append(Double(cols[index("Novelty_Curve")]) ?? 0)
            if hasMFCC {
                mfcc1.append(Double(cols[index("MFCC_1")]) ?? 0)
            }
        }

        guard !times.isEmpty else { throw AnalysisError.emptyAudio }
        let duration = times.last ?? 0

        var series: [FeatureSeries] = [
            makeSeries(.rms, times: times, values: rms),
            makeSeries(.novelty, times: times, values: novelty),
            makeSeries(.centroid, times: times, values: centroid),
            makeSeries(.zcr, times: times, values: zcr)
        ]
        if hasMFCC {
            series.append(makeSeries(.mfcc1, times: times, values: mfcc1))
        }

        let score: ScoreDocument
        let scoreURL: URL?
        if let existing = ScoreStore.load(beside: url) {
            score = existing
            scoreURL = ScoreStore.url(beside: url)
        } else {
            let built = ScoreBuilder.build(
                sourceName: url.lastPathComponent,
                duration: duration,
                times: times,
                rms: rms,
                centroid: centroid,
                zcr: zcr,
                novelty: novelty
            )
            score = built
            scoreURL = try? ScoreStore.save(built, beside: url)
        }

        return AnalysisResult(
            sourceName: url.lastPathComponent,
            sourceURL: url,
            sampleRate: targetSampleRate,
            duration: duration,
            hopLength: hopLength,
            frameLength: frameLength,
            series: series,
            csvURL: url,
            score: score,
            scoreURL: scoreURL
        )
    }

    // MARK: - Loading

    private struct MonoBuffer {
        let samples: [Float]
        let sampleRate: Double
    }

    private func loadMono(url: URL, targetSampleRate: Double) throws -> MonoBuffer {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AnalysisError.readFailed(error.localizedDescription)
        }

        let sourceFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AnalysisError.unsupportedFormat
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AnalysisError.unsupportedFormat
        }

        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else {
            throw AnalysisError.emptyAudio
        }
        try file.read(into: inputBuffer)

        let ratio = targetSampleRate / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            throw AnalysisError.unsupportedFormat
        }

        var error: NSError?
        var consumedInput = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error { throw AnalysisError.readFailed(error.localizedDescription) }

        guard let channel = outputBuffer.floatChannelData?[0] else {
            throw AnalysisError.emptyAudio
        }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
        return MonoBuffer(samples: samples, sampleRate: targetSampleRate)
    }

    // MARK: - Framing & features

    private func frameSignal(_ samples: [Float], frameLength: Int, hopLength: Int) -> [[Float]] {
        guard samples.count >= frameLength else { return [] }
        var frames: [[Float]] = []
        var start = 0
        let window = hannWindow(frameLength)
        while start + frameLength <= samples.count {
            var frame = Array(samples[start..<(start + frameLength)])
            vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(frameLength))
            frames.append(frame)
            start += hopLength
        }
        return frames
    }

    private func hannWindow(_ n: Int) -> [Float] {
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        return window
    }

    private static func rms(_ frame: [Float]) -> Double {
        var meanSquare: Float = 0
        vDSP_measqv(frame, 1, &meanSquare, vDSP_Length(frame.count))
        return Double(sqrtf(meanSquare))
    }

    private static func zeroCrossingRate(_ frame: [Float]) -> Double {
        guard frame.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<frame.count {
            let a = frame[i - 1]
            let b = frame[i]
            if (a >= 0 && b < 0) || (a < 0 && b >= 0) {
                crossings += 1
            }
        }
        return Double(crossings) / Double(frame.count)
    }

    private static func magnitudeSpectrum(_ frame: [Float], fftSize: Int) -> [Float] {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return [Float](repeating: 0, count: fftSize / 2)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var windowed = frame
        if windowed.count < fftSize {
            windowed.append(contentsOf: repeatElement(Float(0), count: fftSize - windowed.count))
        }

        var realp = [Float](repeating: 0, count: fftSize / 2)
        var imagp = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)

        realp.withUnsafeMutableBufferPointer { realBuf in
            imagp.withUnsafeMutableBufferPointer { imagBuf in
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    let complexPtr = raw.bindMemory(to: DSPComplex.self).baseAddress!
                    vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(fftSize / 2))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var count = Int32(magnitudes.count)
        var output = magnitudes
        vvsqrtf(&output, magnitudes, &count)
        return output
    }

    private static func spectralCentroid(magnitude: [Float], sampleRate: Double, fftSize: Int) -> Double {
        let n = magnitude.count
        guard n > 1 else { return 0 }
        var weightedSum: Double = 0
        var sum: Double = 0
        let binHz = sampleRate / Double(fftSize)
        for i in 0..<n {
            let m = Double(magnitude[i])
            weightedSum += m * (Double(i) * binHz)
            sum += m
        }
        guard sum > 1e-12 else { return 0 }
        return weightedSum / sum
    }

    /// Half-wave rectified spectral flux — practical stand-in for librosa onset_strength.
    private static func spectralFluxNovelty(_ spectra: [[Float]]) -> [Double] {
        guard let first = spectra.first else { return [] }
        var values = [Double](repeating: 0, count: spectra.count)
        var prev = first
        for i in 1..<spectra.count {
            let cur = spectra[i]
            var flux: Float = 0
            let n = min(prev.count, cur.count)
            for k in 0..<n {
                let diff = cur[k] - prev[k]
                if diff > 0 { flux += diff }
            }
            values[i] = Double(flux)
            prev = cur
        }
        if let maxV = values.max(), maxV > 10 {
            let scale = maxV / 8.0
            values = values.map { $0 / scale }
        }
        return values
    }

    /// Simplified first MFCC coefficient via mel-band log-energy + DCT-ish projection.
    private static func mfccFirst(magnitude: [Float], sampleRate: Double, fftSize: Int) -> Double {
        let bands = 26
        let n = magnitude.count
        guard n > 2 else { return 0 }
        var melEnergies = [Double](repeating: 0, count: bands)
        let maxHz = sampleRate / 2
        let maxMel = hzToMel(maxHz)
        for b in 0..<bands {
            let mel0 = maxMel * Double(b) / Double(bands + 1)
            let mel1 = maxMel * Double(b + 1) / Double(bands + 1)
            let mel2 = maxMel * Double(b + 2) / Double(bands + 1)
            let f0 = melToHz(mel0)
            let f1 = melToHz(mel1)
            let f2 = melToHz(mel2)
            var energy: Double = 0
            for i in 0..<n {
                let hz = Double(i) * sampleRate / Double(fftSize)
                var w: Double = 0
                if hz >= f0 && hz <= f1 {
                    w = (hz - f0) / max(f1 - f0, 1)
                } else if hz > f1 && hz <= f2 {
                    w = (f2 - hz) / max(f2 - f1, 1)
                }
                energy += Double(magnitude[i]) * w
            }
            melEnergies[b] = log(max(energy, 1e-10))
        }
        // DCT-II coefficient 1 (skip c0)
        var c1: Double = 0
        for b in 0..<bands {
            c1 += melEnergies[b] * cos(.pi * Double(1) * (Double(b) + 0.5) / Double(bands))
        }
        return c1
    }

    private static func hzToMel(_ hz: Double) -> Double {
        2595 * log10(1 + hz / 700)
    }

    private static func melToHz(_ mel: Double) -> Double {
        700 * (pow(10, mel / 2595) - 1)
    }

    private func makeSeries(_ kind: FeatureSeries.Kind, times: [Double], values: [Double]) -> FeatureSeries {
        let points = zip(times, values).enumerated().map { idx, pair in
            FeaturePoint(id: idx, time: pair.0, value: pair.1)
        }
        return FeatureSeries(kind: kind, points: points)
    }

    // MARK: - CSV

    private func writeCSV(
        beside audioURL: URL,
        times: [Double],
        rms: [Double],
        centroid: [Double],
        zcr: [Double],
        novelty: [Double],
        mfcc1: [Double]
    ) throws -> URL {
        let out = audioURL.deletingPathExtension().appendingPathExtension("wos.csv")
        var lines = ["Time_Seconds,RMS_Energy,Spectral_Centroid,ZCR,Novelty_Curve,MFCC_1"]
        for i in 0..<times.count {
            lines.append(String(
                format: "%.6f,%.8f,%.6f,%.8f,%.8f,%.6f",
                times[i], rms[i], centroid[i], zcr[i], novelty[i], mfcc1[i]
            ))
        }
        try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    private func splitCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                result.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        result.append(current)
        return result
    }
}
