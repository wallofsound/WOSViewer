import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppKit

@MainActor
final class AnalysisViewModel: ObservableObject {
    enum MainTab: String, CaseIterable, Identifiable {
        case features = "Features"
        case score = "Score"
        var id: String { rawValue }
    }

    @Published var result: AnalysisResult?
    @Published var score: ScoreDocument?
    @Published var selectedTab: MainTab = .features
    @Published var isAnalyzing = false
    @Published var statusMessage = "Öppna en ljudfil (wav / mp3 / m4a) eller en feature-CSV."
    @Published var errorMessage: String?

    private let analyzer = AudioAnalyzer()

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .wav, .mp3, .mpeg4Audio, .aiff,
            UTType(filenameExtension: "m4a") ?? .mpeg4Audio,
            .commaSeparatedText,
            UTType(filenameExtension: "csv") ?? .commaSeparatedText
        ]
        panel.message = "Välj ljudfil eller CSV (WOS / SEMA)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await analyze(url: url) }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }
            Task { @MainActor in
                await self.analyze(url: url)
            }
        }
        return true
    }

    func analyze(url: URL) async {
        isAnalyzing = true
        errorMessage = nil
        statusMessage = "Analyserar \(url.lastPathComponent)…"
        result = nil
        score = nil

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
            isAnalyzing = false
        }

        do {
            let analysis: AnalysisResult
            let ext = url.pathExtension.lowercased()
            if ext == "csv" {
                analysis = try analyzer.analyzeCSV(at: url)
            } else {
                analysis = try await Task.detached(priority: .userInitiated) {
                    try AudioAnalyzer().analyzeAudio(at: url)
                }.value
            }
            result = analysis
            score = analysis.score
            selectedTab = .features
            let objCount = analysis.score.objects.count
            if let csv = analysis.csvURL, ext != "csv" {
                statusMessage = "Klar. CSV + score (\(objCount) objekt)."
                _ = csv
            } else {
                statusMessage = "Klar — \(analysis.series.first?.points.count ?? 0) ramar, \(objCount) score-objekt"
            }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Misslyckades"
        }
    }

    func saveScore() {
        guard var doc = score else { return }
        doc.sourceName = result?.sourceName ?? doc.sourceName
        score = doc
        if let url = result?.sourceURL ?? result?.csvURL {
            do {
                let out = try ScoreStore.save(doc, beside: url)
                statusMessage = "Score sparad: \(out.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            errorMessage = "Ingen källfil att spara score bredvid."
        }
    }

    func exportPNG(from view: NSView) {
        guard let result else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = result.sourceName + "_Feature_Plots.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let size = view.bounds.size
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        statusMessage = "PNG sparad: \(url.lastPathComponent)"
    }
}

struct ContentView: View {
    @StateObject private var model = AnalysisViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if model.isAnalyzing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(model.statusMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = model.result {
                VStack(spacing: 0) {
                    Picker("Vy", selection: $model.selectedTab) {
                        ForEach(AnalysisViewModel.MainTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    switch model.selectedTab {
                    case .features:
                        ScrollView {
                            FeaturePlotView(result: result)
                                .padding(12)
                        }
                    case .score:
                        ScoreEditorView(
                            score: Binding(
                                get: { model.score ?? result.score },
                                set: { model.score = $0 }
                            ),
                            sourceURL: result.sourceURL?.pathExtension.lowercased() == "csv" ? nil : result.sourceURL,
                            featureSeries: result.series,
                            spectrogram: result.spectrogram,
                            onSave: { _ in model.saveScore() },
                            onStatus: { model.statusMessage = $0 }
                        )
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 900, minHeight: 720)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: model.handleDrop)
        .alert("Fel", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Image("WOSLogo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(height: 22)
                .accessibilityLabel("WallofSound")

            Text("WOS Viewer")
                .font(.headline)

            Button {
                model.openPanel()
            } label: {
                Label("Öppna fil…", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)

            if model.result != nil {
                ExportPNGButton(model: model)
            }

            Spacer()

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("WOSLogo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .accessibilityLabel("WallofSound AB")

                Text("WOS Viewer")
                    .font(.title2.weight(.semibold))

                Text("WallofSound feature + score viewer — ladda wav / mp3 / m4a för features och spektromorfologisk score.\nDu kan också öppna en färdig feature-CSV.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)

                Button("Öppna fil…") { model.openPanel() }
                    .buttonStyle(.borderedProminent)

                featureGlossary
                    .frame(maxWidth: 560)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var featureGlossary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vad mäter graferna?")
                .font(.headline)

            glossaryRow(
                title: "RMS Energy",
                text: "Övergripande ljudstyrka / intensitet."
            )
            glossaryRow(
                title: "Spectral Centroid",
                text: "Upplevd ljusstyrka i klangen (högre värde = ljusare)."
            )
            glossaryRow(
                title: "Zero-Crossing Rate (ZCR)",
                text: "Grad av brusighet kontra tonalitet (högre = brusigare / mer perkussivt, lägre = mer tonalt / uthållet)."
            )
            glossaryRow(
                title: "Novelty Curve",
                text: "Takt av tydliga ljudförändringar / anslag (toppar betyder “nyhet” eller aktivitet)."
            )
            glossaryRow(
                title: "MFCCs",
                text: "Mel-Frequency Cepstral Coefficients — kompakt beskrivning av klangfärg / textur. MFCC₁ visas som kurva; används också vid score-förslag."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func glossaryRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ExportPNGButton: View {
    @ObservedObject var model: AnalysisViewModel

    var body: some View {
        Button("Exportera PNG…") {
            // Find the plot hosting view via key window content
            guard let window = NSApp.keyWindow,
                  let content = window.contentView else { return }
            model.exportPNG(from: content)
        }
    }
}

struct FeaturePlotView: View {
    let result: AnalysisResult

    private let colors: [FeatureSeries.Kind: Color] = [
        .rms: Color(red: 0.10, green: 0.20, blue: 0.55),
        .novelty: Color(red: 0.15, green: 0.55, blue: 0.25),
        .centroid: Color(red: 0.55, green: 0.15, blue: 0.12),
        .zcr: Color(red: 0.55, green: 0.15, blue: 0.55),
        .mfcc1: Color(red: 0.15, green: 0.45, blue: 0.55)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            VStack(spacing: 10) {
                ForEach(Array(result.series.enumerated()), id: \.element.id) { index, series in
                    singleChart(series, showXAxis: index == result.series.count - 1)
                        .frame(minHeight: 150)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func singleChart(_ series: FeatureSeries, showXAxis: Bool) -> some View {
        // Downsample for Chart performance on long pieces
        let points = downsample(series.points, maxPoints: 2_500)
        let color = colors[series.kind] ?? .accentColor

        VStack(alignment: .leading, spacing: 2) {
            Text(series.kind.rawValue)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)

            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.time),
                    y: .value(series.kind.yLabel, point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.0))
            }
            .chartXAxis {
                if showXAxis {
                    AxisMarks(values: .automatic(desiredCount: 8)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let t = value.as(Double.self) {
                                Text("\(Int(t))")
                            }
                        }
                    }
                } else {
                    AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                        AxisGridLine()
                        AxisTick()
                    }
                }
            }
            .chartXAxisLabel(showXAxis ? "Time (Seconds)" : "", position: .bottom, alignment: .center)
            .chartYAxisLabel(series.kind.yLabel, position: .leading)
            .chartYScale(domain: yDomain(for: series))
            .chartPlotStyle { plot in
                plot.background(Color(white: 0.93))
            }
        }
    }

    private func yDomain(for series: FeatureSeries) -> ClosedRange<Double> {
        let values = series.points.map(\.value)
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        // MFCC can be negative
        if series.kind == .mfcc1 {
            let pad = max(abs(maxV - minV) * 0.08, 0.1)
            return (minV - pad)...(maxV + pad)
        }
        let floor = min(0, minV)
        let pad = max(maxV * 0.08, 0.001)
        return floor...(maxV + pad)
    }

    private func downsample(_ points: [FeaturePoint], maxPoints: Int) -> [FeaturePoint] {
        guard points.count > maxPoints else { return points }
        let step = Double(points.count) / Double(maxPoints)
        var out: [FeaturePoint] = []
        out.reserveCapacity(maxPoints)
        var i = 0.0
        while Int(i) < points.count && out.count < maxPoints {
            out.append(points[Int(i)])
            i += step
        }
        return out
    }
}

#Preview {
    ContentView()
}
