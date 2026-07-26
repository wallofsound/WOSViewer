import SwiftUI

struct ScoreEditorView: View {
    @Binding var score: ScoreDocument
    var sourceURL: URL?
    var onSave: (ScoreDocument) -> Void

    @State private var selectedSymbol: ScoreSymbolKind = .pitchedSustained
    @State private var selectedObjectID: ScoreObject.ID?
    @State private var pixelsPerSecond: CGFloat = 28
    @State private var placementArmed = false

    private var selectedBinding: Binding<ScoreObject?> {
        Binding(
            get: {
                guard let id = selectedObjectID else { return nil }
                return score.objects.first { $0.id == id }
            },
            set: { updated in
                guard let updated,
                      let idx = score.objects.firstIndex(where: { $0.id == updated.id }) else { return }
                score.objects[idx] = updated
                score.objects.sort { $0.start < $1.start }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            SymbolPaletteView(selected: $selectedSymbol, placementArmed: $placementArmed)
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
                        pixelsPerSecond: pixelsPerSecond,
                        placementArmed: $placementArmed
                    )
                    .padding(12)
                }
                .background(Color(nsColor: .windowBackgroundColor))
            }

            Divider()

            ScoreInspectorView(
                object: selectedBinding,
                duration: score.duration,
                onDelete: {
                    guard let id = selectedObjectID else { return }
                    score.objects.removeAll { $0.id == id }
                    selectedObjectID = nil
                }
            )
            .frame(width: 220)
        }
    }

    private var scoreToolbar: some View {
        HStack(spacing: 10) {
            Text("Score — \(score.sourceName)")
                .font(.headline)
            Text("\(score.objects.count) objekt")
                .font(.caption)
                .foregroundStyle(.secondary)

            if placementArmed {
                Text("Placeringsläge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

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
            .keyboardShortcut(.delete, modifiers: [])

            Button("Spara score") {
                onSave(score)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct SymbolPaletteView: View {
    @Binding var selected: ScoreSymbolKind
    @Binding var placementArmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symbolpalett")
                .font(.headline)
            Text("Thoresen-inspirerad (förenklad)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Toggle("Placera med klick", isOn: $placementArmed)
                .toggleStyle(.switch)
                .font(.caption)

            ForEach(ScoreSymbolKind.allCases) { kind in
                Button {
                    selected = kind
                    placementArmed = true
                } label: {
                    HStack(spacing: 8) {
                        ScoreSymbolGlyph(kind: kind, filled: true, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(kind.labelSV)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Text(kind.mass.labelSV)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected == kind && placementArmed ? Color.accentColor.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("Dra objekt för att flytta. Handtag för längd. Inspector till höger.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ScoreInspectorView: View {
    @Binding var object: ScoreObject?
    var duration: Double
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector")
                .font(.headline)

            if let obj = Binding($object) {
                Group {
                    labeled("Etikett") {
                        TextField("A", text: obj.label)
                    }

                    labeled("Symbol") {
                        Picker("Symbol", selection: obj.symbol) {
                            ForEach(ScoreSymbolKind.allCases) { kind in
                                Text(kind.labelSV).tag(kind)
                            }
                        }
                        .labelsHidden()
                    }

                    Toggle("Fylld (annars öppen)", isOn: obj.filled)

                    labeled("Lane (0=hög)") {
                        Stepper(value: obj.lane, in: 0...2) {
                            Text("\(obj.wrappedValue.lane)")
                        }
                    }

                    labeled("Start (s)") {
                        TextField(
                            "start",
                            value: obj.start,
                            format: .number.precision(.fractionLength(2))
                        )
                    }

                    labeled("Slut (s)") {
                        TextField(
                            "end",
                            value: obj.end,
                            format: .number.precision(.fractionLength(2))
                        )
                    }

                    labeled("Notering") {
                        TextEditor(text: obj.note)
                            .font(.caption)
                            .frame(minHeight: 70)
                            .border(Color.secondary.opacity(0.3))
                    }

                    if obj.wrappedValue.autoGenerated {
                        Text("Auto-genererad — redigera fritt")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button("Radera objekt", role: .destructive, action: onDelete)
                }
                .onChange(of: object?.start) { _, _ in clampSelection() }
                .onChange(of: object?.end) { _, _ in clampSelection() }
            } else {
                Text("Inget objekt valt.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text("Klicka ett objekt i scoret, eller aktivera placering och klicka i canvas.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func clampSelection() {
        guard var obj = object else { return }
        obj.start = min(max(0, obj.start), max(0, duration - 0.05))
        obj.end = min(max(obj.start + 0.05, obj.end), duration)
        object = obj
    }
}

struct ScoreCanvasView: View {
    @Binding var score: ScoreDocument
    var selectedSymbol: ScoreSymbolKind
    @Binding var selectedObjectID: ScoreObject.ID?
    var pixelsPerSecond: CGFloat
    @Binding var placementArmed: Bool

    private let laneHeight: CGFloat = 56
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

            ForEach(score.timeFields) { field in
                Rectangle()
                    .fill(field.color.opacity(0.45))
                    .frame(
                        width: max(2, x(field.end) - x(field.start)),
                        height: objectAreaHeight
                    )
                    .offset(x: x(field.start), y: rulerHeight)
                    .allowsHitTesting(false)
            }

            ruler
                .allowsHitTesting(false)

            ForEach(0..<laneCount, id: \.self) { lane in
                Path { path in
                    let y = rulerHeight + CGFloat(lane + 1) * laneHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasWidth, y: y))
                }
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                .allowsHitTesting(false)
            }

            ForEach(score.objects) { obj in
                DraggableScoreObjectView(
                    object: binding(for: obj.id),
                    selected: selectedObjectID == obj.id,
                    pixelsPerSecond: pixelsPerSecond,
                    laneHeight: laneHeight,
                    rulerHeight: rulerHeight,
                    laneCount: laneCount,
                    scoreDuration: score.duration,
                    onSelect: {
                        selectedObjectID = obj.id
                        placementArmed = false
                    }
                )
            }

            ForEach(score.dynamicForms) { form in
                dynamicFormView(form)
                    .offset(y: rulerHeight + objectAreaHeight)
                    .allowsHitTesting(false)
            }

            ForEach(score.brackets) { bracket in
                bracketView(bracket)
                    .offset(y: rulerHeight + objectAreaHeight + envelopeHeight)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvasWidth, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard placementArmed else {
                selectedObjectID = nil
                return
            }
            placeObject(at: location)
            placementArmed = false
        }
    }

    private func binding(for id: ScoreObject.ID) -> Binding<ScoreObject> {
        Binding(
            get: {
                score.objects.first { $0.id == id }
                    ?? ScoreObject(label: "?", start: 0, end: 0.1, symbol: .pitchedImpulse)
            },
            set: { updated in
                guard let idx = score.objects.firstIndex(where: { $0.id == id }) else { return }
                score.objects[idx] = updated
                score.objects.sort { $0.start < $1.start }
            }
        )
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

    private func dynamicFormView(_ form: DynamicForm) -> some View {
        let w = max(8, x(form.end) - x(form.start))
        let h = envelopeHeight - 10
        return Canvas { context, _ in
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
        let t = max(0, min(score.duration - 0.5, Double((location.x - 8) / pixelsPerSecond)))
        let laneY = location.y - rulerHeight
        guard laneY >= 0, laneY < objectAreaHeight else { return }
        let lane = min(laneCount - 1, max(0, Int(laneY / laneHeight)))
        let obj = ScoreObject(
            label: nextLabel(),
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

// MARK: - Draggable object

private struct DraggableScoreObjectView: View {
    @Binding var object: ScoreObject
    var selected: Bool
    var pixelsPerSecond: CGFloat
    var laneHeight: CGFloat
    var rulerHeight: CGFloat
    var laneCount: Int
    var scoreDuration: Double
    var onSelect: () -> Void

    @State private var dragStart: ScoreObject?
    @State private var resizeEdge: ResizeEdge?

    private enum ResizeEdge {
        case start, end
    }

    private var width: CGFloat {
        max(28, CGFloat(object.end - object.start) * pixelsPerSecond)
    }

    private var x: CGFloat {
        CGFloat(object.start) * pixelsPerSecond + 8
    }

    private var y: CGFloat {
        rulerHeight + CGFloat(object.lane) * laneHeight + 10
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 4) {
                Text(object.label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                ScoreSymbolGlyph(kind: object.symbol, filled: object.filled, size: 16)
                if width > 54 {
                    Rectangle()
                        .fill(object.filled ? Color.primary : Color.clear)
                        .frame(height: object.filled ? 2 : 1)
                        .overlay(
                            Rectangle()
                                .stroke(
                                    style: StrokeStyle(lineWidth: 1, dash: object.filled ? [] : [4, 3])
                                )
                                .foregroundStyle(Color.primary)
                        )
                }
            }
            .padding(.horizontal, 6)
            .frame(width: width, height: 34, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(selected ? Color.orange : Color.primary.opacity(0.35), lineWidth: selected ? 2 : 1)
            )

            if selected {
                resizeHandle
                    .offset(x: -4)
                    .gesture(resizeGesture(edge: .start))
                resizeHandle
                    .offset(x: width - 4)
                    .gesture(resizeGesture(edge: .end))
            }
        }
        .frame(width: width, height: 34, alignment: .leading)
        .offset(x: x, y: y)
        .highPriorityGesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    onSelect()
                    if dragStart == nil {
                        dragStart = object
                        resizeEdge = nil
                    }
                    guard let origin = dragStart else { return }
                    let dt = Double(value.translation.width / pixelsPerSecond)
                    let dLane = Int(round(Double(value.translation.height / laneHeight)))
                    let dur = origin.end - origin.start
                    var start = origin.start + dt
                    start = min(max(0, start), max(0, scoreDuration - dur))
                    object.start = start
                    object.end = start + dur
                    object.lane = min(laneCount - 1, max(0, origin.lane + dLane))
                    object.autoGenerated = false
                }
                .onEnded { _ in
                    dragStart = nil
                }
        )
        .onTapGesture {
            onSelect()
        }
    }

    private var resizeHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.orange)
            .frame(width: 8, height: 22)
            .contentShape(Rectangle())
    }

    private func resizeGesture(edge: ResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                onSelect()
                if dragStart == nil {
                    dragStart = object
                    resizeEdge = edge
                }
                guard let origin = dragStart, resizeEdge == edge else { return }
                let dt = Double(value.translation.width / pixelsPerSecond)
                switch edge {
                case .start:
                    let newStart = min(origin.end - 0.08, max(0, origin.start + dt))
                    object.start = newStart
                case .end:
                    let newEnd = max(origin.start + 0.08, min(scoreDuration, origin.end + dt))
                    object.end = newEnd
                }
                object.autoGenerated = false
            }
            .onEnded { _ in
                dragStart = nil
                resizeEdge = nil
            }
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
                let path = Path(ellipseIn: rect.insetBy(dx: 2, dy: 2))
                if filled { context.fill(path, with: .color(color)) }
                else { context.stroke(path, with: .color(color), lineWidth: 1.5) }
            case .pitchedSustained:
                let head = CGRect(x: rect.minX, y: rect.midY - 4, width: 8, height: 8)
                let oval = Path(ellipseIn: head)
                if filled { context.fill(oval, with: .color(color)) }
                else { context.stroke(oval, with: .color(color), lineWidth: 1.5) }
                var line = Path()
                line.move(to: CGPoint(x: head.maxX, y: rect.midY))
                line.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                context.stroke(line, with: .color(color), lineWidth: 1.5)
            case .complexImpulse:
                let path = Path(roundedRect: rect.insetBy(dx: 3, dy: 3), cornerRadius: 1)
                if filled { context.fill(path, with: .color(color)) }
                else { context.stroke(path, with: .color(color), lineWidth: 1.5) }
            case .complexSustained:
                let head = CGRect(x: rect.minX, y: rect.midY - 4, width: 8, height: 8)
                let box = Path(roundedRect: head, cornerRadius: 1)
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
                    let p = Path(ellipseIn: CGRect(x: cx, y: cy, width: 3, height: 3))
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
