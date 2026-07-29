import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoreGraphics

enum ScoreExportFormat: String, CaseIterable, Identifiable {
    case png, pdf, svg
    var id: String { rawValue }

    var label: String {
        switch self {
        case .png: return "PNG…"
        case .pdf: return "PDF…"
        case .svg: return "SVG…"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .pdf: return .pdf
        case .svg: return UTType(filenameExtension: "svg") ?? .xml
        }
    }

    var pathExtension: String { rawValue }
}

enum ScoreExportError: LocalizedError {
    case renderFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: return "Kunde inte skapa export."
        case .writeFailed: return "Kunde inte spara filen."
        }
    }
}

@MainActor
enum ScoreExporter {
    static func presentSave(
        score: ScoreDocument,
        format: ScoreExportFormat,
        pixelsPerSecond: CGFloat,
        spectrogram: SpectrogramData?,
        objectVisibility: Double,
        showNashville: Bool = false,
        onStatus: ((String) -> Void)?
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        let base = score.sourceName
            .replacingOccurrences(of: ".wav", with: "")
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".aiff", with: "")
        panel.nameFieldStringValue = "\(base)_Score.\(format.pathExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            switch format {
            case .png:
                try writePNG(
                    to: url,
                    score: score,
                    pixelsPerSecond: pixelsPerSecond,
                    spectrogram: spectrogram,
                    objectVisibility: objectVisibility,
                    showNashville: showNashville
                )
            case .pdf:
                try writePDF(
                    to: url,
                    score: score,
                    pixelsPerSecond: pixelsPerSecond,
                    spectrogram: spectrogram,
                    objectVisibility: objectVisibility,
                    showNashville: showNashville
                )
            case .svg:
                try writeSVG(
                    to: url,
                    score: score,
                    pixelsPerSecond: pixelsPerSecond,
                    spectrogram: spectrogram,
                    objectVisibility: objectVisibility,
                    showNashville: showNashville
                )
            }
            onStatus?("Score-\(format.rawValue.uppercased()) sparad: \(url.lastPathComponent)")
        } catch {
            onStatus?(error.localizedDescription)
        }
    }

    // MARK: - PNG / PDF via SwiftUI ImageRenderer (Viewer-stil)

    private static func exportView(
        score: ScoreDocument,
        pixelsPerSecond: CGFloat,
        spectrogram: SpectrogramData?,
        objectVisibility: Double,
        showNashville: Bool
    ) -> some View {
        ScoreExportView(
            score: score,
            pixelsPerSecond: max(pixelsPerSecond, 24),
            spectrogram: spectrogram,
            objectVisibility: objectVisibility,
            showNashville: showNashville
        )
        .padding(16)
        .background(Color.white)
    }

    private static func writePNG(
        to url: URL,
        score: ScoreDocument,
        pixelsPerSecond: CGFloat,
        spectrogram: SpectrogramData?,
        objectVisibility: Double,
        showNashville: Bool
    ) throws {
        let renderer = ImageRenderer(
            content: exportView(
                score: score,
                pixelsPerSecond: pixelsPerSecond,
                spectrogram: spectrogram,
                objectVisibility: objectVisibility,
                showNashville: showNashville
            )
        )
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ScoreExportError.renderFailed
        }
        try png.write(to: url, options: .atomic)
    }

    private static func writePDF(
        to url: URL,
        score: ScoreDocument,
        pixelsPerSecond: CGFloat,
        spectrogram: SpectrogramData?,
        objectVisibility: Double,
        showNashville: Bool
    ) throws {
        let renderer = ImageRenderer(
            content: exportView(
                score: score,
                pixelsPerSecond: pixelsPerSecond,
                spectrogram: spectrogram,
                objectVisibility: objectVisibility,
                showNashville: showNashville
            )
        )
        renderer.scale = 2

        var wrote = false
        renderer.render { size, draw in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            ctx.beginPDFPage(nil)
            draw(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            wrote = true
        }
        guard wrote, FileManager.default.fileExists(atPath: url.path) else {
            throw ScoreExportError.renderFailed
        }
    }

    private static func writeSVG(
        to url: URL,
        score: ScoreDocument,
        pixelsPerSecond: CGFloat,
        spectrogram: SpectrogramData?,
        objectVisibility: Double,
        showNashville: Bool
    ) throws {
        let svg = ScoreSVGBuilder.build(
            score: score,
            pixelsPerSecond: max(pixelsPerSecond, 24),
            spectrogram: spectrogram,
            objectVisibility: objectVisibility,
            showNashville: showNashville
        )
        guard let data = svg.data(using: .utf8) else { throw ScoreExportError.renderFailed }
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - SVG builder

enum ScoreSVGBuilder {
    private static let laneHeight: CGFloat = 56
    private static let laneCount = 3
    private static let fieldStripHeight: CGFloat = 22
    private static let envelopeHeight: CGFloat = 70
    private static let rulerHeight: CGFloat = 24
    private static let bracketHeight: CGFloat = 28
    private static let pad: CGFloat = 16

    static func build(
        score: ScoreDocument,
        pixelsPerSecond: CGFloat,
        spectrogram: SpectrogramData?,
        objectVisibility: Double,
        showNashville: Bool = false
    ) -> String {
        let canvasW = max(CGFloat(score.duration) * pixelsPerSecond + 80, 600)
        let objectH = CGFloat(laneCount) * laneHeight
        let objectTop = rulerHeight + fieldStripHeight
        let canvasH = rulerHeight + fieldStripHeight + objectH + envelopeHeight + bracketHeight + 16
        let titleH: CGFloat = 28
        let totalW = canvasW + pad * 2
        let totalH = canvasH + pad * 2 + titleH

        func x(_ t: Double) -> CGFloat { CGFloat(t) * pixelsPerSecond + 8 }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        let visible = score.objects.filter { obj in
            if objectVisibility <= 0.001 { return false }
            if objectVisibility >= 0.999 { return true }
            return obj.rmsEnergy + 1e-6 >= (1.0 - objectVisibility)
        }

        var out: [String] = []
        out.append(#"<?xml version="1.0" encoding="UTF-8"?>"#)
        out.append(
            #"<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" "# +
            #"width="\#(Int(totalW.rounded()))" height="\#(Int(totalH.rounded()))" "# +
            #"viewBox="0 0 \#(fmt(totalW)) \#(fmt(totalH))">"#
        )
        out.append("<title>WOS Viewer — \(esc(score.sourceName))</title>")
        out.append("<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>")
        out.append(
            "<text x=\"\(fmt(pad))\" y=\"\(fmt(pad + 18))\" " +
            "font-family=\"Helvetica, Arial, sans-serif\" font-size=\"16\" font-weight=\"600\" fill=\"#111\">" +
            "WOS Viewer — \(esc(score.sourceName))</text>"
        )

        let ox = pad
        let oy = pad + titleH

        // Canvas background
        out.append(
            "<rect x=\"\(fmt(ox))\" y=\"\(fmt(oy))\" width=\"\(fmt(canvasW))\" height=\"\(fmt(canvasH))\" " +
            "rx=\"6\" fill=\"#ffffff\" stroke=\"#ddd\"/>"
        )

        // Spectrogram (optional embedded PNG)
        if let spectrogram, let img = spectrogramPNGDataURL(spectrogram) {
            let sw = max(1, CGFloat(score.duration) * pixelsPerSecond)
            out.append(
                "<image x=\"\(fmt(ox + 8))\" y=\"\(fmt(oy + objectTop))\" " +
                "width=\"\(fmt(sw))\" height=\"\(fmt(objectH))\" " +
                "preserveAspectRatio=\"none\" opacity=\"0.85\" xlink:href=\"\(img)\"/>"
            )
        }

        // Time-field wash
        for field in score.timeFields {
            let color = field.colorHex
            let w = max(2, x(field.end) - x(field.start))
            out.append(
                "<rect x=\"\(fmt(ox + x(field.start)))\" y=\"\(fmt(oy + objectTop))\" " +
                "width=\"\(fmt(w))\" height=\"\(fmt(objectH))\" fill=\"\(color)\" opacity=\"0.28\"/>"
            )
        }

        // Ruler
        out.append(
            "<rect x=\"\(fmt(ox))\" y=\"\(fmt(oy))\" width=\"\(fmt(canvasW))\" " +
            "height=\"\(fmt(rulerHeight))\" fill=\"#f0f0f0\"/>"
        )
        var t = 0.0
        while t <= score.duration + 0.001 {
            let px = ox + x(t)
            out.append(
                "<line x1=\"\(fmt(px))\" y1=\"\(fmt(oy + rulerHeight - 8))\" " +
                "x2=\"\(fmt(px))\" y2=\"\(fmt(oy + rulerHeight))\" stroke=\"#888\" stroke-width=\"1\"/>"
            )
            out.append(
                "<text x=\"\(fmt(px + 2))\" y=\"\(fmt(oy + 14))\" " +
                "font-family=\"Menlo, monospace\" font-size=\"9\" fill=\"#666\">\(Int(t))</text>"
            )
            t += 5
        }

        // Field strip labels
        for field in score.timeFields {
            let w = max(20, x(field.end) - x(field.start))
            out.append(
                "<rect x=\"\(fmt(ox + x(field.start)))\" y=\"\(fmt(oy + rulerHeight + 2))\" " +
                "width=\"\(fmt(w))\" height=\"\(fmt(fieldStripHeight - 4))\" " +
                "rx=\"3\" fill=\"\(field.colorHex)\" opacity=\"0.85\" stroke=\"#00000040\"/>"
            )
            out.append(
                "<text x=\"\(fmt(ox + x(field.start) + 6))\" y=\"\(fmt(oy + rulerHeight + 15))\" " +
                "font-family=\"Helvetica, Arial, sans-serif\" font-size=\"10\" font-weight=\"600\" fill=\"#222\">" +
                "\(esc(field.name))</text>"
            )
        }

        // Lane lines
        for lane in 0..<laneCount {
            let y = oy + objectTop + CGFloat(lane + 1) * laneHeight
            out.append(
                "<line x1=\"\(fmt(ox))\" y1=\"\(fmt(y))\" x2=\"\(fmt(ox + canvasW))\" y2=\"\(fmt(y))\" " +
                "stroke=\"#00000020\" stroke-width=\"0.5\"/>"
            )
        }

        // Objects
        for obj in visible {
            let w = max(24, CGFloat(obj.end - obj.start) * pixelsPerSecond)
            let px = ox + x(obj.start)
            let py = oy + objectTop + CGFloat(obj.lane) * laneHeight + 8
            out.append("<g transform=\"translate(\(fmt(px)),\(fmt(py)))\">")
            out.append(
                "<text x=\"0\" y=\"14\" font-family=\"Menlo, monospace\" font-size=\"11\" " +
                "font-weight=\"700\" fill=\"#111\">\(esc(obj.label))</text>"
            )
            if showNashville, !obj.nashville.isEmpty {
                out.append(
                    "<text x=\"14\" y=\"14\" font-family=\"Helvetica, Arial, sans-serif\" font-size=\"10\" " +
                    "font-weight=\"600\" fill=\"#c45c12\">\(esc(obj.nashville))</text>"
                )
                out.append(contentsOf: symbolSVG(kind: obj.symbol, filled: obj.filled, x: 28, y: 2))
            } else {
                out.append(contentsOf: symbolSVG(kind: obj.symbol, filled: obj.filled, x: 16, y: 2))
            }
            if w > 40 {
                let lineY: CGFloat = 14
                let x0: CGFloat = 40
                let x1 = w - 2
                if obj.filled {
                    out.append(
                        "<line x1=\"\(fmt(x0))\" y1=\"\(fmt(lineY))\" x2=\"\(fmt(x1))\" y2=\"\(fmt(lineY))\" " +
                        "stroke=\"#111\" stroke-width=\"1.5\"/>"
                    )
                } else {
                    out.append(
                        "<line x1=\"\(fmt(x0))\" y1=\"\(fmt(lineY))\" x2=\"\(fmt(x1))\" y2=\"\(fmt(lineY))\" " +
                        "stroke=\"#111\" stroke-width=\"1\" stroke-dasharray=\"3 2\"/>"
                    )
                }
            }
            out.append("</g>")
        }

        // Dynamic forms
        let formY = oy + objectTop + objectH + 4
        for form in score.dynamicForms {
            let w = max(12, x(form.end) - x(form.start))
            let h = envelopeHeight - 10
            let fx = ox + x(form.start)
            let path = formPath(shape: form.shape, width: w, height: h, intensity: form.intensity)
            out.append(
                "<path d=\"\(path)\" transform=\"translate(\(fmt(fx)),\(fmt(formY)))\" " +
                "fill=\"#00000024\" stroke=\"#0000008C\" stroke-width=\"1\"/>"
            )
        }

        // Brackets
        let brY = oy + objectTop + objectH + envelopeHeight + 4
        for bracket in score.brackets {
            let w = max(10, x(bracket.end) - x(bracket.start))
            let bx = ox + x(bracket.start)
            out.append(
                "<path d=\"M0 10 L0 2 L\(fmt(w)) 2 L\(fmt(w)) 10\" " +
                "transform=\"translate(\(fmt(bx)),\(fmt(brY)))\" " +
                "fill=\"none\" stroke=\"#111\" stroke-width=\"1.2\"/>"
            )
            if !bracket.label.isEmpty {
                out.append(
                    "<text x=\"\(fmt(bx))\" y=\"\(fmt(brY + 22))\" " +
                    "font-family=\"Helvetica, Arial, sans-serif\" font-size=\"9\" fill=\"#666\">" +
                    "\(esc(bracket.label))</text>"
                )
            }
        }

        out.append("</svg>")
        return out.joined(separator: "\n")
    }

    private static func formPath(shape: DynamicForm.Shape, width: CGFloat, height h: CGFloat, intensity: Double) -> String {
        let w = width
        switch shape {
        case .crescendo:
            return "M0 \(fmt(h)) L\(fmt(w)) \(fmt(h * 0.15)) L\(fmt(w)) \(fmt(h)) Z"
        case .diminuendo:
            return "M0 \(fmt(h * 0.15)) L\(fmt(w)) \(fmt(h)) L0 \(fmt(h)) Z"
        case .swell:
            let mid = h * (1 - 0.7 * min(1.2, intensity))
            return "M0 \(fmt(h)) L\(fmt(w * 0.5)) \(fmt(mid)) L\(fmt(w)) \(fmt(h)) Z"
        case .plateau:
            let top = h * (0.55 - 0.2 * min(1.2, intensity))
            return "M0 \(fmt(top)) H\(fmt(w)) V\(fmt(h - 4)) H0 Z"
        }
    }

    private static func symbolSVG(kind: ScoreSymbolKind, filled: Bool, x: CGFloat, y: CGFloat) -> [String] {
        let s: CGFloat = 16
        var lines: [String] = []
        let fill = filled ? "#111" : "none"
        let stroke = "#111"
        switch kind {
        case .pitchedImpulse:
            lines.append(
                "<circle cx=\"\(fmt(x + s / 2))\" cy=\"\(fmt(y + s / 2))\" r=\"5\" " +
                "fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"1.5\"/>"
            )
        case .pitchedSustained:
            lines.append(
                "<circle cx=\"\(fmt(x + 5))\" cy=\"\(fmt(y + s / 2))\" r=\"4\" " +
                "fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"1.5\"/>"
            )
            lines.append(
                "<line x1=\"\(fmt(x + 9))\" y1=\"\(fmt(y + s / 2))\" x2=\"\(fmt(x + s))\" y2=\"\(fmt(y + s / 2))\" " +
                "stroke=\"\(stroke)\" stroke-width=\"1.5\"/>"
            )
        case .complexImpulse:
            lines.append(
                "<rect x=\"\(fmt(x + 3))\" y=\"\(fmt(y + 3))\" width=\"10\" height=\"10\" rx=\"1\" " +
                "fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"1.5\"/>"
            )
        case .complexSustained:
            lines.append(
                "<rect x=\"\(fmt(x + 1))\" y=\"\(fmt(y + 4))\" width=\"8\" height=\"8\" rx=\"1\" " +
                "fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"1.5\"/>"
            )
            lines.append(
                "<line x1=\"\(fmt(x + 9))\" y1=\"\(fmt(y + s / 2))\" x2=\"\(fmt(x + s))\" y2=\"\(fmt(y + s / 2))\" " +
                "stroke=\"\(stroke)\" stroke-width=\"1.5\" stroke-dasharray=\"3 2\"/>"
            )
        case .iterated:
            for i in 0..<3 {
                let cx = x + CGFloat(i) * 6 + 3
                let cy = y + s / 2
                lines.append(
                    "<polygon points=\"\(fmt(cx)),\(fmt(cy - 3)) \(fmt(cx + 3)),\(fmt(cy)) " +
                    "\(fmt(cx)),\(fmt(cy + 3)) \(fmt(cx - 3)),\(fmt(cy))\" fill=\"#111\"/>"
                )
            }
        case .accumulation:
            for i in 0..<5 {
                let cx = x + 3 + CGFloat(i % 3) * 5
                let cy = y + 4 + CGFloat(i / 3) * 6
                lines.append("<circle cx=\"\(fmt(cx))\" cy=\"\(fmt(cy))\" r=\"1.5\" fill=\"#111\"/>")
            }
        case .variable:
            let midx = x + s / 2
            let midy = y + s / 2
            lines.append(
                "<polygon points=\"\(fmt(x + 2)),\(fmt(midy)) \(fmt(midx)),\(fmt(y + 2)) " +
                "\(fmt(x + s - 2)),\(fmt(midy)) \(fmt(midx)),\(fmt(y + s - 2))\" " +
                "fill=\"none\" stroke=\"#111\" stroke-width=\"1.5\"/>"
            )
        case .stratified:
            for i in 0..<3 {
                let ly = y + 4 + CGFloat(i) * 5
                lines.append(
                    "<line x1=\"\(fmt(x))\" y1=\"\(fmt(ly))\" x2=\"\(fmt(x + s))\" y2=\"\(fmt(ly))\" " +
                    "stroke=\"#111\" stroke-width=\"1.2\"/>"
                )
            }
        }
        return lines
    }

    private static func spectrogramPNGDataURL(_ data: SpectrogramData) -> String? {
        guard let cg = data.makeCGImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    private static func fmt(_ v: CGFloat) -> String {
        String(format: "%.2f", Double(v))
    }
}
