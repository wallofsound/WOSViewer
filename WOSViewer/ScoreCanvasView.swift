import SwiftUI

struct ScoreEditorView: View {
    @Binding var score: ScoreDocument
    var sourceURL: URL?
    var onSave: (ScoreDocument) -> Void

    @State private var selectedSymbol: ScoreSymbolKind = .pitchedSustained
    @State private var selectedObjectID: ScoreObject.ID?
    @State private var pixelsPerSecond: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            SymbolPaletteView(selected: $selectedSymbol)
                .frame(width: 168)

            Divider()

            VStack(spacing: 0) {
                scoreToolbar
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    ScoreCanvasView(
                        score: $score,
                        selectedSymbol: selectedSymbol,
                        selectedObjectID: $selectedObjectID,
                        pixelsPerSecond: pixelsPerSecond
                    )
                    .padding(12)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var scoreToolbar: some View {
        HStack(spacing: 10) {
            Text("Score — \(score.sourceName)")
                .font(.headline)
            Text("\(score.objects.count) objekt")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Slider(value: $pixelsPerSecond, in: 12...80) {
                Text("Zoom")
            }
            .frame(width: 140)

            Button("Radera valt") {
                guard let id = selectedObjectID else { return }
                score.objects.removeAll { $0.id == id }
                selectedObjectID = nil
            }
            .disabled(selectedObjectID == nil)

            Button("Spara score") {
                onSave(score)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SymbolPaletteView: View {
    @Binding var selected: ScoreSymbolKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symbolpalett")
                .font(.headline)
            Text("Thoresen-inspirerad (förenklad)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            ForEach(ScoreSymbolKind.allCases) { kind in
                Button {
                    selected = kind
                } label: {
                    HStack(spacing: 8) {
                        ScoreSymbolGlyph(kind: kind, filled: true, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.labelSV)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text("\(kind.mass.labelSV)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected == kind ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("Klicka i canvas för att placera. Dubbelklick växlar fylld/öppen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ScoreCanvasView: View {
    @Binding var score: ScoreDocument
    var selectedSymbol: ScoreSymbolKind
    @Binding var selectedObjectID: ScoreObject.ID?
    var pixelsPerSecond: CGFloat

    private let laneHeight: CGFloat = 52
    private let laneCount = 3
    private let envelopeHeight: CGFloat = 70
    private let rulerHeight: CGFloat = 24
    private let bracketHeight: CGFloat = 28

    private var canvasWidth: CGFloat {
        max(CGFloat(score.duration) * pixelsPerSecond + 80, 600)
    }

    private var objectAreaHeight: CGFloat { CGFloat(laneCount) * laneHeight }

    private var totalHeight: CGFloat {
        rulerHeight + objectAreaHeight + envelopeHeight + bracketHeight + 16
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.97))
                .frame(width: canvasWidth, height: totalHeight)

            // Time fields
            ForEach(score.timeFields) { field in
                Rectangle()
                    .fill(field.color.opacity(0.45))
                    .frame(
                        width: max(2, x(field.end) - x(field.start)),
                        height: objectAreaHeight
                    )
                    .offset(x: x(field.start), y: rulerHeight)
            }

            // Grid + ruler
            ruler
                .offset(y: 0)

            // Lane lines
            ForEach(0..<laneCount, id: \.self) { lane in
                Path { path in
                    let y = rulerHeight + CGFloat(lane + 1) * laneHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasWidth, y: y))
                }
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
            }

            // Objects
            ForEach(score.objects) { obj in
                objectView(obj)
            }

            // Dynamic forms
            ForEach(score.dynamicForms) { form in
                dynamicFormView(form)
                    .offset(y: rulerHeight + objectAreaHeight)
            }

            // Brackets
            ForEach(score.brackets) { bracket in
                bracketView(bracket)
                    .offset(y: rulerHeight + objectAreaHeight + envelopeHeight)
            }
        }
        .frame(width: canvasWidth, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { location in
            placeObject(at: location)
        }
    }

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(white: 0.92))
                .frame(width: canvasWidth, height: rulerHeight)

            ForEach(Array(stride(from: 0.0, through: score.duration, by: 5.0)), id: \.self) { t in
                let px = x(t)
                Path { p in
                    p.move(to: CGPoint(x: px, y: rulerHeight - 8))
                    p.addLine(to: CGPoint(x: px, y: rulerHeight))
                }
                .stroke(Color.secondary, lineWidth: 1)

                Text("\(Int(t))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .offset(x: px + 2, y: 4)
            }
        }
        .frame(width: canvasWidth, height: rulerHeight, alignment: .topLeading)
    }

    private func objectView(_ obj: ScoreObject) -> some View {
        let w = max(18, x(obj.end) - x(obj.start))
        let y = rulerHeight + CGFloat(obj.lane) * laneHeight + 10
        let selected = selectedObjectID == obj.id

        return HStack(spacing: 4) {
            Text(obj.label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            ScoreSymbolGlyph(kind: obj.symbol, filled: obj.filled, size: 16)
            if w > 50 {
                Rectangle()
                    .fill(obj.filled ? Color.primary : Color.clear)
                    .frame(height: obj.filled ? 2 : 1)
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: obj.filled ? [] : [4, 3]))
                            .foregroundStyle(Color.primary)
                    )
            }
        }
        .padding(.horizontal, 4)
        .frame(width: w, height: 32, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(selected ? Color.orange : Color.clear, lineWidth: 2)
        )
        .offset(x: x(obj.start), y: y)
        .gesture(
            TapGesture(count: 2).onEnded {
                if let idx = score.objects.firstIndex(where: { $0.id == obj.id }) {
                    score.objects[idx].filled.toggle()
                }
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                selectedObjectID = obj.id
            }
        )
    }

    private func dynamicFormView(_ form: DynamicForm) -> some View {
        let w = max(8, x(form.end) - x(form.start))
        let h = envelopeHeight - 10
        return Canvas { context, size in
            var path = Path()
            switch form.shape {
            case .crescendo:
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: w, y: h * 0.15))
                path.addLine(to: CGPoint(x: w, y: h))
            case .diminuendo:
                path.move(to: CGPoint(x: 0, y: h * 0.15))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
            case .swell:
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.1))
                path.addLine(to: CGPoint(x: w, y: h))
            case .plateau:
                path.addRect(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.2))
            }
            context.fill(path, with: .color(.black.opacity(0.12)))
            context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1)
        }
        .frame(width: w, height: h)
        .offset(x: x(form.start), y: 4)
    }

    private func bracketView(_ bracket: ScoreBracket) -> some View {
        let w = max(10, x(bracket.end) - x(bracket.start))
        return VStack(spacing: 2) {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 10))
                p.addLine(to: CGPoint(x: 0, y: 2))
                p.addLine(to: CGPoint(x: w, y: 2))
                p.addLine(to: CGPoint(x: w, y: 10))
            }
            .stroke(Color.primary, lineWidth: 1.2)
            .frame(width: w, height: 12)

            if !bracket.label.isEmpty {
                Text(bracket.label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .offset(x: x(bracket.start), y: 4)
    }

    private func x(_ time: Double) -> CGFloat {
        CGFloat(time) * pixelsPerSecond + 8
    }

    private func placeObject(at location: CGPoint) {
        // Ignore taps on toolbar-ish top ruler only for placement if too high? Allow all.
        let t = max(0, min(score.duration - 0.5, Double((location.x - 8) / pixelsPerSecond)))
        let laneY = location.y - rulerHeight
        guard laneY >= 0, laneY < objectAreaHeight else { return }
        let lane = min(laneCount - 1, max(0, Int(laneY / laneHeight)))
        let label = nextLabel()
        let obj = ScoreObject(
            label: label,
            start: t,
            end: min(score.duration, t + 1.5),
            lane: lane,
            symbol: selectedSymbol,
            filled: true,
            note: "manuell",
            autoGenerated: false
        )
        score.objects.append(obj)
        score.objects.sort { $0.start < $1.start }
        selectedObjectID = obj.id
    }

    private func nextLabel() -> String {
        let used = Set(score.objects.map(\.label))
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let s = String(ch)
            if !used.contains(s) { return s }
        }
        return "X\(score.objects.count + 1)"
    }
}

struct ScoreSymbolGlyph: View {
    let kind: ScoreSymbolKind
    let filled: Bool
    var size: CGFloat = 16

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(x: 2, y: 2, width: canvasSize.width - 4, height: canvasSize.height - 4)
            let color = Color.primary
            switch kind {
            case .pitchedImpulse:
                var path = Path(ellipseIn: rect.insetBy(dx: 2, dy: 2))
                if filled { context.fill(path, with: .color(color)) }
                else { context.stroke(path, with: .color(color), lineWidth: 1.5) }
            case .pitchedSustained:
                let head = CGRect(x: rect.minX, y: rect.midY - 4, width: 8, height: 8)
                var oval = Path(ellipseIn: head)
                if filled { context.fill(oval, with: .color(color)) }
                else { context.stroke(oval, with: .color(color), lineWidth: 1.5) }
                var line = Path()
                line.move(to: CGPoint(x: head.maxX, y: rect.midY))
                line.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.stroke(line, with: .color(color), lineWidth: 1.5)
            case .complexImpulse:
                var path = Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 1)
                if filled { context.fill(path, with: .color(color)) }
                else { context.stroke(path, with: .color(color), lineWidth: 1.5) }
            case .complexSustained:
                let head = CGRect(x: rect.minX, y: rect.midY - 4, width: 8, height: 8)
                var box = Path(roundedRect: head, cornerRadius: 1)
                if filled { context.fill(box, with: .color(color)) }
                else { context.stroke(box, with: .color(color), lineWidth: 1.5) }
                var line = Path()
                line.move(to: CGPoint(x: head.maxX, y: rect.midY))
                line.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.stroke(
                    line,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                )
            case .iterated:
                for i in 0..<3 {
                    let r = CGRect(
                        x: rect.minX + CGFloat(i) * 6,
                        y: rect.midY - 3,
                        width: 6,
                        height: 6
                    )
                    var d = Path()
                    d.move(to: CGPoint(x: r.midX, y: r.minY))
                    d.addLine(to: CGPoint(x: r.maxX, y: r.midY))
                    d.addLine(to: CGPoint(x: r.midX, y: r.maxY))
                    d.addLine(to: CGPoint(x: r.minX, y: r.midY))
                    d.closeSubpath()
                    context.fill(d, with: .color(color))
                }
            case .accumulation:
                for i in 0..<5 {
                    let cx = rect.minX + 3 + CGFloat(i % 3) * 5
                    let cy = rect.minY + 4 + CGFloat(i / 3) * 6
                    var p = Path(ellipseIn: CGRect(x: cx, y: cy, width: 3, height: 3))
                    context.fill(p, with: .color(color))
                }
            case .variable:
                var d = Path()
                d.move(to: CGPoint(x: rect.minX + 2, y: rect.midY))
                d.addLine(to: CGPoint(x: rect.midX, y: rect.minY + 2))
                d.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY))
                d.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 2))
                d.closeSubpath()
                context.stroke(d, with: .color(color), lineWidth: 1.5)
                var arrow = Path()
                arrow.move(to: CGPoint(x: rect.maxX - 6, y: rect.minY + 2))
                arrow.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 6))
                context.stroke(arrow, with: .color(color), lineWidth: 1.2)
            case .stratified:
                for i in 0..<3 {
                    var line = Path()
                    let y = rect.minY + 4 + CGFloat(i) * 5
                    line.move(to: CGPoint(x: rect.minX, y: y))
                    line.addLine(to: CGPoint(x: rect.maxX, y: y))
                    context.stroke(line, with: .color(color), lineWidth: 1.2)
                }
            }
        }
        .frame(width: size + 4, height: size)
    }
}
