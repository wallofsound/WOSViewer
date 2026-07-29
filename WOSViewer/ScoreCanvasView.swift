import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ScorePresentationMode: String, CaseIterable, Identifiable {
    case edit = "Edit"
    case view = "Viewer"
    var id: String { rawValue }
}

enum ScoreEditSelection: Hashable {
    case none
    case object(ScoreObject.ID)
    case timeField(TimeField.ID)
    case dynamicForm(DynamicForm.ID)
}

enum PlacementTool: Hashable {
    case none
    case symbol(ScoreSymbolKind)
    case timeField
    case dynamicForm(DynamicForm.Shape)
}

struct ScoreEditorView: View {
    @Binding var score: ScoreDocument
    var sourceURL: URL?
    var featureSeries: [FeatureSeries]? = nil
    var spectrogram: SpectrogramData? = nil
    var onSave: (ScoreDocument) -> Void
    var onStatus: ((String) -> Void)? = nil

    @State private var selectedSymbol: ScoreSymbolKind = .pitchedSustained
    @State private var selectedFormShape: DynamicForm.Shape = .crescendo
    @State private var selection: ScoreEditSelection = .none
    @State private var placementTool: PlacementTool = .none
    @State private var pixelsPerSecond: CGFloat = 28
    @State private var objectVisibility: Double = 1
    @State private var isInteracting = false
    @State private var presentation: ScorePresentationMode = .edit
    @State private var showSpectrogram = true
    @State private var didEnrichEnergies = false
    @StateObject private var player = ScoreAudioPlayer()
    @FocusState private var canvasFocused: Bool

    private var isEditing: Bool { presentation == .edit }

    private var visibleObjects: [ScoreObject] {
        score.objects.filter { Self.isObjectVisible($0, visibility: objectVisibility) }
    }

    private static func isObjectVisible(_ obj: ScoreObject, visibility: Double) -> Bool {
        if visibility <= 0.001 { return false }
        if visibility >= 0.999 { return true }
        // Låg energi försvinner först när reglaget går mot 0.
        return obj.rmsEnergy + 1e-6 >= (1.0 - visibility)
    }

    private var selectedObjectBinding: Binding<ScoreObject?> {
        Binding(
            get: {
                if case .object(let id) = selection {
                    return score.objects.first { $0.id == id }
                }
                return nil
            },
            set: { updated in
                guard let updated,
                      let idx = score.objects.firstIndex(where: { $0.id == updated.id }) else { return }
                score.objects[idx] = updated
                if !isInteracting {
                    score.objects.sort { $0.start < $1.start }
                }
            }
        )
    }

    private var selectedFieldBinding: Binding<TimeField?> {
        Binding(
            get: {
                if case .timeField(let id) = selection {
                    return score.timeFields.first { $0.id == id }
                }
                return nil
            },
            set: { updated in
                guard let updated,
                      let idx = score.timeFields.firstIndex(where: { $0.id == updated.id }) else { return }
                score.timeFields[idx] = updated
                if !isInteracting {
                    score.timeFields.sort { $0.start < $1.start }
                }
            }
        )
    }

    private var selectedFormBinding: Binding<DynamicForm?> {
        Binding(
            get: {
                if case .dynamicForm(let id) = selection {
                    return score.dynamicForms.first { $0.id == id }
                }
                return nil
            },
            set: { updated in
                guard let updated,
                      let idx = score.dynamicForms.firstIndex(where: { $0.id == updated.id }) else { return }
                score.dynamicForms[idx] = updated
                if !isInteracting {
                    score.dynamicForms.sort { $0.start < $1.start }
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            if isEditing {
                ScorePaletteView(
                    selectedSymbol: $selectedSymbol,
                    selectedFormShape: $selectedFormShape,
                    placementTool: $placementTool
                )
                .frame(width: 176)
                Divider()
            }

            VStack(spacing: 0) {
                scoreToolbar
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    ScoreCanvasView(
                        score: score,
                        selection: $selection,
                        placementTool: $placementTool,
                        selectedSymbol: selectedSymbol,
                        selectedFormShape: selectedFormShape,
                        pixelsPerSecond: pixelsPerSecond,
                        objectVisibility: objectVisibility,
                        isInteracting: $isInteracting,
                        presentation: presentation,
                        spectrogram: spectrogram,
                        showSpectrogram: showSpectrogram,
                        playheadTime: player.hasAudio ? player.currentTime : nil,
                        onSeek: { t in
                            player.seek(to: t, duration: score.duration)
                        },
                        onChangeObject: { updated in
                            guard let idx = score.objects.firstIndex(where: { $0.id == updated.id }) else { return }
                            score.objects[idx] = updated
                        },
                        onChangeField: { updated in
                            guard let idx = score.timeFields.firstIndex(where: { $0.id == updated.id }) else { return }
                            score.timeFields[idx] = updated
                        },
                        onChangeForm: { updated in
                            guard let idx = score.dynamicForms.firstIndex(where: { $0.id == updated.id }) else { return }
                            score.dynamicForms[idx] = updated
                        },
                        onPlaceObject: { obj in
                            var placed = obj
                            if let series = featureSeries {
                                placed.rmsEnergy = ScoreBuilder.rmsEnergy(
                                    start: placed.start,
                                    end: placed.end,
                                    from: series
                                )
                            }
                            score.objects.append(placed)
                            score.objects.sort { $0.start < $1.start }
                            selection = .object(placed.id)
                        },
                        onPlaceField: { field in
                            score.timeFields.append(field)
                            score.timeFields.sort { $0.start < $1.start }
                            selection = .timeField(field.id)
                        },
                        onPlaceForm: { form in
                            score.dynamicForms.append(form)
                            score.dynamicForms.sort { $0.start < $1.start }
                            selection = .dynamicForm(form.id)
                        },
                        onInteractionEnded: {
                            score.objects.sort { $0.start < $1.start }
                            score.timeFields.sort { $0.start < $1.start }
                            score.dynamicForms.sort { $0.start < $1.start }
                        }
                    )
                    .padding(12)
                }
                .scrollDisabled(isInteracting)
                .background(Color(nsColor: .windowBackgroundColor))
                .focusable()
                .focused($canvasFocused)
                .onDeleteCommand(perform: deleteSelected)
                .onAppear {
                    canvasFocused = true
                    player.prepare(url: sourceURL)
                    enrichEnergiesIfNeeded()
                }
                .onChange(of: selection) { _, _ in canvasFocused = true }
                .onChange(of: sourceURL) { _, url in player.prepare(url: url) }
                .onChange(of: featureSeries?.count) { _, _ in
                    didEnrichEnergies = false
                    enrichEnergiesIfNeeded()
                }
            }

            if isEditing {
                Divider()
                ScoreInspectorView(
                    object: selectedObjectBinding,
                    timeField: selectedFieldBinding,
                    dynamicForm: selectedFormBinding,
                    duration: score.duration,
                    onDelete: deleteSelected,
                    onPlaySegment: playSelectedSegment
                )
                .frame(width: 240)
            }
        }
        .onAppear { canvasFocused = true }
        .onDisappear { player.stop() }
    }

    private func playSelectedSegment() {
        switch selection {
        case .object(let id):
            if let obj = score.objects.first(where: { $0.id == id }) {
                player.play(from: obj.start, to: obj.end)
            }
        case .timeField(let id):
            if let field = score.timeFields.first(where: { $0.id == id }) {
                player.play(from: field.start, to: field.end)
            }
        case .dynamicForm(let id):
            if let form = score.dynamicForms.first(where: { $0.id == id }) {
                player.play(from: form.start, to: form.end)
            }
        case .none:
            break
        }
    }

    private func deleteSelected() {
        guard isEditing else { return }
        switch selection {
        case .object(let id):
            score.objects.removeAll { $0.id == id }
        case .timeField(let id):
            score.timeFields.removeAll { $0.id == id }
        case .dynamicForm(let id):
            score.dynamicForms.removeAll { $0.id == id }
        case .none:
            return
        }
        selection = .none
    }

    private func enrichEnergiesIfNeeded() {
        guard !didEnrichEnergies, let series = featureSeries else { return }
        score = ScoreBuilder.enrichEnergies(score, from: series)
        didEnrichEnergies = true
    }

    private func reanalyze() {
        guard let series = featureSeries else {
            onStatus?("Ingen feature-data för omanalys.")
            return
        }
        let auto = ScoreBuilder.build(
            from: series,
            sourceName: score.sourceName,
            duration: score.duration
        )
        let merged = ScoreBuilder.mergeKeepingManual(auto: auto, previous: score)
        score = ScoreBuilder.enrichEnergies(merged, from: series)
        didEnrichEnergies = true
        selection = .none
        let manualN = merged.objects.filter { !$0.autoGenerated }.count
            + merged.timeFields.filter { !$0.autoGenerated }.count
            + merged.dynamicForms.filter { !$0.autoGenerated }.count
        onStatus?(
            "Omanalys klar — \(merged.objects.filter(\.autoGenerated).count) auto-objekt, \(manualN) manuella element behållna."
        )
    }

    private var scoreToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Score — \(score.sourceName)")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Picker("", selection: $presentation) {
                    ForEach(ScorePresentationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .onChange(of: presentation) { _, mode in
                    if mode == .view {
                        placementTool = .none
                        selection = .none
                    }
                }

                Text("\(visibleObjects.count)/\(score.objects.count) obj · \(score.timeFields.count) fält · \(score.dynamicForms.count) former")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                playbackControls
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Zoom")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $pixelsPerSecond, in: 12...80)
                        .frame(width: 110)
                }

                HStack(spacing: 6) {
                    Text("Objekt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $objectVisibility, in: 0...1)
                        .frame(width: 110)
                    Text("\(Int((objectVisibility * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .help("Objektsiktbarhet via energi (RMS). 100% = alla, 0% = inga. Svagare objekt försvinner först.")

                Toggle("Spektrogram", isOn: $showSpectrogram)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .help(spectrogram == nil
                          ? "Spektrogram finns bara vid ljudanalys (inte CSV)."
                          : "Mel-spektrogram under objektplanen (låg frekvens nederst).")
                    .disabled(spectrogram == nil)

                Spacer(minLength: 8)

                if isEditing {
                    Button("Omanalysera") { reanalyze() }
                        .help("Ny auto-analys från features. Manuella objekt/fält/former behålls.")
                        .disabled(featureSeries == nil)

                    Button("Radera (⌫)") { deleteSelected() }
                        .disabled(selection == .none)
                        .keyboardShortcut(.delete, modifiers: [])

                    Button("Spara") { onSave(score) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("s", modifiers: .command)
                }

                Button("PNG…") { exportScorePNG() }
                    .help("Exporterar score i Viewer-stil (utan editrutor).")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var playbackControls: some View {
        HStack(spacing: 4) {
            Button {
                player.togglePlay(duration: score.duration)
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(sourceURL == nil)
            .help("Spela / pausa från playhead. Dra orange linje eller linjalen för startposition.")

            Button { playSelectedSegment() } label: {
                Image(systemName: "play.circle")
            }
            .disabled(sourceURL == nil || selection == .none)
            .help("Spela markerat objekt / fält / form")

            Button { player.stop() } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(sourceURL == nil)

            if player.currentTime > 0 || player.isPlaying {
                Text(String(format: "%.1fs", player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func exportScorePNG() {
        let exportView = ScoreExportView(
            score: score,
            pixelsPerSecond: max(pixelsPerSecond, 24),
            spectrogram: showSpectrogram ? spectrogram : nil,
            objectVisibility: objectVisibility
        )
            .padding(16)
            .background(Color.white)

        let renderer = ImageRenderer(content: exportView)
        renderer.scale = 2

        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            onStatus?("Kunde inte skapa PNG.")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = score.sourceName + "_Score.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try png.write(to: url)
            onStatus?("Score-PNG sparad: \(url.lastPathComponent)")
        } catch {
            onStatus?("PNG-export misslyckades.")
        }
    }
}

// MARK: - Export (always Viewer chrome)

struct ScoreExportView: View {
    let score: ScoreDocument
    var pixelsPerSecond: CGFloat = 28
    var spectrogram: SpectrogramData? = nil
    var objectVisibility: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WOS Viewer — \(score.sourceName)")
                .font(.headline)
            ScoreCanvasView(
                score: score,
                selection: .constant(.none),
                placementTool: .constant(.none),
                selectedSymbol: .pitchedSustained,
                selectedFormShape: .crescendo,
                pixelsPerSecond: pixelsPerSecond,
                objectVisibility: objectVisibility,
                isInteracting: .constant(false),
                presentation: .view,
                spectrogram: spectrogram,
                showSpectrogram: spectrogram != nil,
                playheadTime: nil,
                onSeek: nil,
                onChangeObject: { _ in },
                onChangeField: { _ in },
                onChangeForm: { _ in },
                onPlaceObject: { _ in },
                onPlaceField: { _ in },
                onPlaceForm: { _ in },
                onInteractionEnded: {}
            )
        }
    }
}

// MARK: - Palette / Inspector

struct ScorePaletteView: View {
    @Binding var selectedSymbol: ScoreSymbolKind
    @Binding var selectedFormShape: DynamicForm.Shape
    @Binding var placementTool: PlacementTool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Palett")
                    .font(.headline)
                Text("Thoresen-inspirerad (förenklad)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                sectionTitle("Objekt")
                ForEach(ScoreSymbolKind.allCases) { kind in
                    Button {
                        selectedSymbol = kind
                        placementTool = .symbol(kind)
                    } label: {
                        HStack(spacing: 8) {
                            ScoreSymbolGlyph(kind: kind, filled: true, size: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.labelSV).font(.caption)
                                Text(kind.mass.labelSV).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(pill(active: {
                            if case .symbol(let s) = placementTool { return s == kind }
                            return false
                        }()))
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                sectionTitle("Tidsfält")
                Button {
                    placementTool = .timeField
                } label: {
                    Label("Placera tidsfält", systemImage: "rectangle.split.3x1")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(6)
                        .background(pill(active: placementTool == .timeField))
                }
                .buttonStyle(.plain)
                Text("Färgade zoner i tid (time-fields).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Divider()

                sectionTitle("Dynamisk form")
                ForEach(DynamicForm.Shape.allCases) { shape in
                    Button {
                        selectedFormShape = shape
                        placementTool = .dynamicForm(shape)
                    } label: {
                        Text(shape.labelSV)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(pill(active: {
                                if case .dynamicForm(let s) = placementTool { return s == shape }
                                return false
                            }()))
                    }
                    .buttonStyle(.plain)
                }
                Text("Kuvert under objektplanen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if placementTool != .none {
                    Button("Avbryt placering") { placementTool = .none }
                        .font(.caption)
                }

                Text("Edit = rutor/handtag. Viewer = rent partitur. PNG = alltid Viewer. ⌫ lämnar tidshål.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func pill(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(active ? Color.accentColor.opacity(0.15) : Color.clear)
    }
}

struct ScoreInspectorView: View {
    @Binding var object: ScoreObject?
    @Binding var timeField: TimeField?
    @Binding var dynamicForm: DynamicForm?
    var duration: Double
    var onDelete: () -> Void
    var onPlaySegment: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspector").font(.headline)

            if let obj = Binding($object) {
                objectInspector(obj)
            } else if let field = Binding($timeField) {
                fieldInspector(field)
            } else if let form = Binding($dynamicForm) {
                formInspector(form)
            } else {
                Text("Inget valt.")
                    .foregroundStyle(.secondary)
                Text("Markera objekt, tidsfält eller dynamisk form i Edit.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func objectInspector(_ obj: Binding<ScoreObject>) -> some View {
        labeled("Etikett") { TextField("A", text: obj.label) }
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
            Stepper(value: obj.lane, in: 0...2) { Text("\(obj.wrappedValue.lane)") }
        }
        timeFields(start: obj.start, end: obj.end)
        labeled("Notering") {
            TextEditor(text: obj.note)
                .font(.caption)
                .frame(minHeight: 70)
                .border(Color.secondary.opacity(0.3))
        }
        actionButtons(title: "Radera objekt (⌫)")
    }

    @ViewBuilder
    private func fieldInspector(_ field: Binding<TimeField>) -> some View {
        labeled("Namn") { TextField("Fält", text: field.name) }
        labeled("Färg") {
            HStack(spacing: 6) {
                ForEach(TimeField.paletteColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(
                                field.wrappedValue.colorHex == hex ? Color.accentColor : Color.clear,
                                lineWidth: 2
                            )
                        )
                        .onTapGesture {
                            field.wrappedValue.colorHex = hex
                            field.wrappedValue.autoGenerated = false
                        }
                }
            }
        }
        timeFields(start: field.start, end: field.end)
            .onChange(of: field.wrappedValue.start) { _, _ in field.wrappedValue.autoGenerated = false }
            .onChange(of: field.wrappedValue.end) { _, _ in field.wrappedValue.autoGenerated = false }
        actionButtons(title: "Radera tidsfält (⌫)")
    }

    @ViewBuilder
    private func formInspector(_ form: Binding<DynamicForm>) -> some View {
        labeled("Form") {
            Picker("Form", selection: form.shape) {
                ForEach(DynamicForm.Shape.allCases) { shape in
                    Text(shape.labelSV).tag(shape)
                }
            }
            .labelsHidden()
        }
        labeled("Intensitet") {
            Slider(value: form.intensity, in: 0.2...1.5)
        }
        timeFields(start: form.start, end: form.end)
        actionButtons(title: "Radera form (⌫)")
    }

    private func timeFields(start: Binding<Double>, end: Binding<Double>) -> some View {
        Group {
            labeled("Start (s)") {
                TextField("start", value: start, format: .number.precision(.fractionLength(2)))
            }
            labeled("Slut (s)") {
                TextField("end", value: end, format: .number.precision(.fractionLength(2)))
            }
        }
    }

    private func actionButtons(title: String) -> some View {
        Group {
            if let onPlaySegment {
                Button("Spela segment", action: onPlaySegment)
            }
            Button(title, role: .destructive, action: onDelete)
            Text("Radering lämnar tidshål. Andra element flyttas inte.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Canvas

struct ScoreCanvasView: View {
    let score: ScoreDocument
    @Binding var selection: ScoreEditSelection
    @Binding var placementTool: PlacementTool
    var selectedSymbol: ScoreSymbolKind
    var selectedFormShape: DynamicForm.Shape
    var pixelsPerSecond: CGFloat
    var objectVisibility: Double = 1
    @Binding var isInteracting: Bool
    var presentation: ScorePresentationMode
    var spectrogram: SpectrogramData? = nil
    var showSpectrogram: Bool = false
    var playheadTime: Double?
    var onSeek: ((Double) -> Void)? = nil
    var onChangeObject: (ScoreObject) -> Void
    var onChangeField: (TimeField) -> Void
    var onChangeForm: (DynamicForm) -> Void
    var onPlaceObject: (ScoreObject) -> Void
    var onPlaceField: (TimeField) -> Void
    var onPlaceForm: (DynamicForm) -> Void
    var onInteractionEnded: () -> Void

    private let laneHeight: CGFloat = 56
    private let laneCount = 3
    private let fieldStripHeight: CGFloat = 22
    private let envelopeHeight: CGFloat = 70
    private let rulerHeight: CGFloat = 24
    private let bracketHeight: CGFloat = 28

    private var isEditing: Bool { presentation == .edit }

    private var visibleObjects: [ScoreObject] {
        score.objects.filter { obj in
            if objectVisibility <= 0.001 { return false }
            if objectVisibility >= 0.999 { return true }
            return obj.rmsEnergy + 1e-6 >= (1.0 - objectVisibility)
        }
    }

    private var canvasWidth: CGFloat {
        max(CGFloat(score.duration) * pixelsPerSecond + 80, 600)
    }

    private var objectAreaHeight: CGFloat { CGFloat(laneCount) * laneHeight }

    private var objectTop: CGFloat { rulerHeight + fieldStripHeight }

    private var totalHeight: CGFloat {
        rulerHeight + fieldStripHeight + objectAreaHeight + envelopeHeight + bracketHeight + 16
    }

    private var spectrogramWidth: CGFloat {
        max(1, CGFloat(score.duration) * pixelsPerSecond)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white)
                .frame(width: canvasWidth, height: totalHeight)

            // Spectrogram underlay behind time-field wash + objects
            if showSpectrogram, let spectrogram {
                SpectrogramUnderlayView(data: spectrogram)
                    .frame(width: spectrogramWidth, height: objectAreaHeight)
                    .offset(x: 8, y: objectTop)
                    .allowsHitTesting(false)
            }

            // Background wash for time fields across object lanes
            ForEach(score.timeFields) { field in
                Rectangle()
                    .fill(field.color.opacity(presentation == .view ? 0.22 : 0.28))
                    .frame(width: max(2, x(field.end) - x(field.start)), height: objectAreaHeight)
                    .offset(x: x(field.start), y: objectTop)
                    .allowsHitTesting(false)
            }

            ruler

            // Editable time-field strip
            ForEach(score.timeFields) { field in
                TimeFieldCanvasItem(
                    field: field,
                    selected: isEditing && selection == .timeField(field.id),
                    pixelsPerSecond: pixelsPerSecond,
                    stripHeight: fieldStripHeight,
                    stripY: rulerHeight,
                    scoreDuration: score.duration,
                    presentation: presentation,
                    onSelect: {
                        guard isEditing else { return }
                        selection = .timeField(field.id)
                        placementTool = .none
                    },
                    onChange: onChangeField,
                    onInteractingChanged: { active in
                        guard isEditing else { return }
                        isInteracting = active
                        if !active { onInteractionEnded() }
                    }
                )
            }

            ForEach(0..<laneCount, id: \.self) { lane in
                Path { path in
                    let y = objectTop + CGFloat(lane + 1) * laneHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: canvasWidth, y: y))
                }
                .stroke(Color.gray.opacity(presentation == .view ? 0.12 : 0.25), lineWidth: 0.5)
                .allowsHitTesting(false)
            }

            ForEach(visibleObjects) { obj in
                ScoreObjectCanvasItem(
                    object: obj,
                    selected: isEditing && selection == .object(obj.id),
                    pixelsPerSecond: pixelsPerSecond,
                    laneHeight: laneHeight,
                    objectTop: objectTop,
                    laneCount: laneCount,
                    scoreDuration: score.duration,
                    presentation: presentation,
                    onSelect: {
                        guard isEditing else { return }
                        selection = .object(obj.id)
                        placementTool = .none
                    },
                    onChange: onChangeObject,
                    onInteractingChanged: { active in
                        guard isEditing else { return }
                        isInteracting = active
                        if !active { onInteractionEnded() }
                    }
                )
            }

            ForEach(score.dynamicForms) { form in
                DynamicFormCanvasItem(
                    form: form,
                    selected: isEditing && selection == .dynamicForm(form.id),
                    pixelsPerSecond: pixelsPerSecond,
                    envelopeHeight: envelopeHeight,
                    envelopeY: objectTop + objectAreaHeight,
                    scoreDuration: score.duration,
                    presentation: presentation,
                    onSelect: {
                        guard isEditing else { return }
                        selection = .dynamicForm(form.id)
                        placementTool = .none
                    },
                    onChange: onChangeForm,
                    onInteractingChanged: { active in
                        guard isEditing else { return }
                        isInteracting = active
                        if !active { onInteractionEnded() }
                    }
                )
            }

            ForEach(score.brackets) { bracket in
                bracketView(bracket)
                    .offset(y: objectTop + objectAreaHeight + envelopeHeight)
                    .allowsHitTesting(false)
            }

            if let t = playheadTime {
                PlayheadView(
                    time: t,
                    pixelsPerSecond: pixelsPerSecond,
                    height: fieldStripHeight + objectAreaHeight + envelopeHeight,
                    scoreDuration: score.duration,
                    enabled: onSeek != nil,
                    onSeek: { newTime in onSeek?(newTime) },
                    onInteractingChanged: { active in
                        isInteracting = active
                    }
                )
                .offset(y: rulerHeight)
                .zIndex(50)
            }
        }
        .frame(width: canvasWidth, height: totalHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard isEditing else { return }
            guard placementTool != .none else {
                selection = .none
                return
            }
            place(at: location)
            placementTool = .none
        }
    }

    private var ruler: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(white: 0.94))
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
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard onSeek != nil else { return }
                    isInteracting = true
                    onSeek?(timeAt(x: value.location.x))
                }
                .onEnded { _ in
                    isInteracting = false
                }
        )
        .help(onSeek == nil ? "" : "Klicka eller dra i linjalen för att sätta startposition.")
    }

    private func timeAt(x px: CGFloat) -> Double {
        let t = Double((px - 8) / pixelsPerSecond)
        return min(max(0, t), max(0, score.duration - 0.01))
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
                Text(bracket.label).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .offset(x: x(bracket.start), y: 4)
    }

    private func x(_ time: Double) -> CGFloat {
        CGFloat(time) * pixelsPerSecond + 8
    }

    private func place(at location: CGPoint) {
        let t = max(0, min(score.duration - 0.4, Double((location.x - 8) / pixelsPerSecond)))
        switch placementTool {
        case .symbol(let kind):
            let laneY = location.y - objectTop
            guard laneY >= 0, laneY < objectAreaHeight else { return }
            let lane = min(laneCount - 1, max(0, Int(laneY / laneHeight)))
            let obj = ScoreObject(
                label: nextObjectLabel(),
                start: t,
                end: min(score.duration, t + 1.5),
                lane: lane,
                symbol: kind,
                filled: true,
                note: "manuell",
                autoGenerated: false
            )
            onPlaceObject(obj)
        case .timeField:
            let field = TimeField(
                start: t,
                end: min(score.duration, t + max(2.0, score.duration * 0.12)),
                name: nextFieldName(),
                colorHex: TimeField.paletteColors[score.timeFields.count % TimeField.paletteColors.count],
                autoGenerated: false
            )
            onPlaceField(field)
        case .dynamicForm(let shape):
            let form = DynamicForm(
                start: t,
                end: min(score.duration, t + max(1.5, score.duration * 0.08)),
                shape: shape,
                intensity: 1,
                autoGenerated: false
            )
            onPlaceForm(form)
        case .none:
            break
        }
    }

    private func nextObjectLabel() -> String {
        let used = Set(score.objects.map(\.label))
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let s = String(ch)
            if !used.contains(s) { return s }
        }
        return "X\(score.objects.count + 1)"
    }

    private func nextFieldName() -> String {
        "Fält \(score.timeFields.count + 1)"
    }
}

// MARK: - Playhead scrubber

private struct PlayheadView: View {
    var time: Double
    var pixelsPerSecond: CGFloat
    var height: CGFloat
    var scoreDuration: Double
    var enabled: Bool
    var onSeek: (Double) -> Void
    var onInteractingChanged: (Bool) -> Void

    @State private var dragOrigin: Double?

    private var xPos: CGFloat { CGFloat(time) * pixelsPerSecond + 8 }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color.orange)
                .frame(width: 2, height: height)
            Capsule()
                .fill(Color.orange)
                .frame(width: 10, height: 14)
                .offset(y: -2)
        }
        .frame(width: 16, height: height, alignment: .top)
        .contentShape(Rectangle())
        .offset(x: xPos - 8)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard enabled else { return }
                    if dragOrigin == nil {
                        dragOrigin = time
                        onInteractingChanged(true)
                    }
                    let dt = Double(value.translation.width / pixelsPerSecond)
                    let t = (dragOrigin ?? time) + dt
                    onSeek(min(max(0, t), max(0, scoreDuration - 0.01)))
                }
                .onEnded { _ in
                    dragOrigin = nil
                    onInteractingChanged(false)
                }
        )
        .help(enabled ? "Dra playhead eller linjalen för startposition. Play fortsätter härifrån. Stop återställer till 0." : "")
        .allowsHitTesting(enabled)
    }
}

// MARK: - Spectrogram underlay

private struct SpectrogramUnderlayView: View {
    let data: SpectrogramData
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.medium)
            } else {
                Color.clear
            }
        }
        .onAppear { image = data.makeCGImage() }
        .onChange(of: data.columnCount) { _, _ in image = data.makeCGImage() }
    }
}

// MARK: - Time field item

private struct TimeFieldCanvasItem: View {
    let field: TimeField
    var selected: Bool
    var pixelsPerSecond: CGFloat
    var stripHeight: CGFloat
    var stripY: CGFloat
    var scoreDuration: Double
    var presentation: ScorePresentationMode
    var onSelect: () -> Void
    var onChange: (TimeField) -> Void
    var onInteractingChanged: (Bool) -> Void

    @State private var draft: TimeField?
    @State private var dragOrigin: TimeField?
    @State private var mode: DragMode = .move

    private enum DragMode { case move, resizeStart, resizeEnd }

    private var live: TimeField { draft ?? field }
    private var width: CGFloat { max(presentation == .view ? 20 : 32, CGFloat(live.end - live.start) * pixelsPerSecond) }
    private var xPos: CGFloat { CGFloat(live.start) * pixelsPerSecond + 8 }
    private var edgeWidth: CGFloat { min(12, max(8, width * 0.18)) }

    var body: some View {
        Group {
            if presentation == .view {
                Text(live.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.7))
                    .frame(width: width, height: stripHeight - 4, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                HStack(spacing: 0) {
                    edgeBar
                        .frame(width: edgeWidth, height: stripHeight - 4)
                        .highPriorityGesture(dragGesture(mode: .resizeStart))

                    Text(live.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .gesture(dragGesture(mode: .move))
                        .onTapGesture { onSelect() }

                    edgeBar
                        .frame(width: edgeWidth, height: stripHeight - 4)
                        .highPriorityGesture(dragGesture(mode: .resizeEnd))
                }
                .frame(width: width, height: stripHeight - 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(live.color.opacity(0.85)))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(selected ? Color.accentColor : Color.primary.opacity(0.25), lineWidth: selected ? 2 : 1)
                )
                .help("Tidsfält: mitten = flytta, kanter = längd.")
            }
        }
        .offset(x: xPos, y: stripY + 2)
    }

    private var edgeBar: some View {
        Rectangle()
            .fill(selected ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.12))
            .contentShape(Rectangle())
    }

    private func dragGesture(mode requested: DragMode) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                onSelect()
                if dragOrigin == nil {
                    dragOrigin = field
                    draft = field
                    mode = requested
                    onInteractingChanged(true)
                }
                guard var working = draft, let origin = dragOrigin else { return }
                let dt = Double(value.translation.width / pixelsPerSecond)
                switch mode {
                case .move:
                    let dur = origin.end - origin.start
                    var start = origin.start + dt
                    start = min(max(0, start), max(0, scoreDuration - dur))
                    working.start = start
                    working.end = start + dur
                case .resizeStart:
                    working.start = min(origin.end - 0.15, max(0, origin.start + dt))
                case .resizeEnd:
                    working.end = max(origin.start + 0.15, min(scoreDuration, origin.end + dt))
                }
                working.autoGenerated = false
                draft = working
                onChange(working)
            }
            .onEnded { _ in
                if let draft { onChange(draft) }
                self.draft = nil
                dragOrigin = nil
                onInteractingChanged(false)
            }
    }
}

// MARK: - Dynamic form item

private struct DynamicFormCanvasItem: View {
    let form: DynamicForm
    var selected: Bool
    var pixelsPerSecond: CGFloat
    var envelopeHeight: CGFloat
    var envelopeY: CGFloat
    var scoreDuration: Double
    var presentation: ScorePresentationMode
    var onSelect: () -> Void
    var onChange: (DynamicForm) -> Void
    var onInteractingChanged: (Bool) -> Void

    @State private var draft: DynamicForm?
    @State private var dragOrigin: DynamicForm?
    @State private var mode: DragMode = .move

    private enum DragMode { case move, resizeStart, resizeEnd }

    private var live: DynamicForm { draft ?? form }
    private var width: CGFloat { max(presentation == .view ? 12 : 28, CGFloat(live.end - live.start) * pixelsPerSecond) }
    private var xPos: CGFloat { CGFloat(live.start) * pixelsPerSecond + 8 }
    private var h: CGFloat { envelopeHeight - 10 }
    private var edgeWidth: CGFloat { min(12, max(8, width * 0.18)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            formShape
                .frame(width: width, height: h)
                .opacity(0.35 + 0.45 * min(1.5, live.intensity) / 1.5)

            if presentation == .edit {
                HStack(spacing: 0) {
                    edgeBar
                        .frame(width: edgeWidth, height: h)
                        .highPriorityGesture(dragGesture(mode: .resizeStart))
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(dragGesture(mode: .move))
                        .onTapGesture { onSelect() }
                    edgeBar
                        .frame(width: edgeWidth, height: h)
                        .highPriorityGesture(dragGesture(mode: .resizeEnd))
                }
                .frame(width: width, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
            }
        }
        .offset(x: xPos, y: envelopeY + 4)
        .help(presentation == .edit ? "Dynamisk form: mitten = flytta, kanter = längd." : live.shape.labelSV)
    }

    private var formShape: some View {
        Canvas { context, _ in
            var path = Path()
            switch live.shape {
            case .crescendo:
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: width, y: h * 0.15))
                path.addLine(to: CGPoint(x: width, y: h))
            case .diminuendo:
                path.move(to: CGPoint(x: 0, y: h * 0.15))
                path.addLine(to: CGPoint(x: width, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
            case .swell:
                path.move(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: width * 0.5, y: h * (1 - 0.7 * min(1.2, live.intensity))))
                path.addLine(to: CGPoint(x: width, y: h))
            case .plateau:
                let top = h * (0.55 - 0.2 * min(1.2, live.intensity))
                path.addRect(CGRect(x: 0, y: top, width: width, height: max(4, h - top - 4)))
            }
            context.fill(path, with: .color(.black.opacity(0.14)))
            context.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 1)
        }
    }

    private var edgeBar: some View {
        Rectangle()
            .fill(selected ? Color.accentColor.opacity(0.35) : Color.black.opacity(0.06))
            .contentShape(Rectangle())
    }

    private func dragGesture(mode requested: DragMode) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                onSelect()
                if dragOrigin == nil {
                    dragOrigin = form
                    draft = form
                    mode = requested
                    onInteractingChanged(true)
                }
                guard var working = draft, let origin = dragOrigin else { return }
                let dt = Double(value.translation.width / pixelsPerSecond)
                switch mode {
                case .move:
                    let dur = origin.end - origin.start
                    var start = origin.start + dt
                    start = min(max(0, start), max(0, scoreDuration - dur))
                    working.start = start
                    working.end = start + dur
                case .resizeStart:
                    working.start = min(origin.end - 0.12, max(0, origin.start + dt))
                case .resizeEnd:
                    working.end = max(origin.start + 0.12, min(scoreDuration, origin.end + dt))
                }
                working.autoGenerated = false
                draft = working
                onChange(working)
            }
            .onEnded { _ in
                if let draft { onChange(draft) }
                self.draft = nil
                dragOrigin = nil
                onInteractingChanged(false)
            }
    }
}

// MARK: - Object item (Edit chrome vs Viewer clean)

private struct ScoreObjectCanvasItem: View {
    let object: ScoreObject
    var selected: Bool
    var pixelsPerSecond: CGFloat
    var laneHeight: CGFloat
    var objectTop: CGFloat
    var laneCount: Int
    var scoreDuration: Double
    var presentation: ScorePresentationMode
    var onSelect: () -> Void
    var onChange: (ScoreObject) -> Void
    var onInteractingChanged: (Bool) -> Void

    @State private var draft: ScoreObject?
    @State private var dragOrigin: ScoreObject?
    @State private var mode: DragMode = .move

    private enum DragMode { case move, resizeStart, resizeEnd }

    private var live: ScoreObject { draft ?? object }

    private var width: CGFloat {
        max(presentation == .view ? 24 : 36, CGFloat(live.end - live.start) * pixelsPerSecond)
    }

    private var xPos: CGFloat { CGFloat(live.start) * pixelsPerSecond + 8 }
    private var yPos: CGFloat { objectTop + CGFloat(live.lane) * laneHeight + 8 }
    private var edgeWidth: CGFloat { min(14, max(10, width * 0.2)) }

    var body: some View {
        Group {
            if presentation == .view {
                viewerBody
            } else {
                editorBody
            }
        }
        .offset(x: xPos, y: yPos)
    }

    private var viewerBody: some View {
        HStack(spacing: 4) {
            Text(live.label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
            ScoreSymbolGlyph(kind: live.symbol, filled: live.filled, size: 16)
            if width > 40 {
                Rectangle()
                    .fill(live.filled ? Color.primary : Color.clear)
                    .frame(height: live.filled ? 1.5 : 1)
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1, dash: live.filled ? [] : [3, 2]))
                            .foregroundStyle(Color.primary)
                    )
            }
        }
        .frame(width: width, height: 28, alignment: .leading)
    }

    private var editorBody: some View {
        HStack(spacing: 0) {
            edgeBar(label: "⟨")
                .frame(width: edgeWidth, height: 38)
                .highPriorityGesture(dragGesture(mode: .resizeStart))

            HStack(spacing: 4) {
                Text(live.label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                ScoreSymbolGlyph(kind: live.symbol, filled: live.filled, size: 16)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(dragGesture(mode: .move))
            .onTapGesture { onSelect() }

            edgeBar(label: "⟩")
                .frame(width: edgeWidth, height: 38)
                .highPriorityGesture(dragGesture(mode: .resizeEnd))
        }
        .frame(width: width, height: 38)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.92)))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(selected ? Color.accentColor : Color.primary.opacity(0.35), lineWidth: selected ? 2 : 1)
        )
        .help("Mitten = flytta. ⟨⟩ = längd. ⌫ = radera.")
    }

    private func edgeBar(label: String) -> some View {
        ZStack {
            Rectangle()
                .fill(selected ? Color.accentColor.opacity(0.35) : Color.gray.opacity(0.2))
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        }
        .contentShape(Rectangle())
    }

    private func dragGesture(mode requested: DragMode) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                onSelect()
                if dragOrigin == nil {
                    dragOrigin = object
                    draft = object
                    mode = requested
                    onInteractingChanged(true)
                }
                guard var working = draft, let origin = dragOrigin else { return }
                let dt = Double(value.translation.width / pixelsPerSecond)
                switch mode {
                case .move:
                    let dLane = Int(round(Double(value.translation.height / laneHeight)))
                    let dur = origin.end - origin.start
                    var start = origin.start + dt
                    start = min(max(0, start), max(0, scoreDuration - dur))
                    working.start = start
                    working.end = start + dur
                    working.lane = min(laneCount - 1, max(0, origin.lane + dLane))
                case .resizeStart:
                    working.start = min(origin.end - 0.08, max(0, origin.start + dt))
                case .resizeEnd:
                    working.end = max(origin.start + 0.08, min(scoreDuration, origin.end + dt))
                }
                working.autoGenerated = false
                draft = working
                onChange(working)
            }
            .onEnded { _ in
                if let draft { onChange(draft) }
                self.draft = nil
                dragOrigin = nil
                onInteractingChanged(false)
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
                context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            case .iterated:
                for i in 0..<3 {
                    let r = CGRect(x: rect.minX + CGFloat(i) * 6, y: rect.midY - 3, width: 6, height: 6)
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
                    context.fill(Path(ellipseIn: CGRect(x: cx, y: cy, width: 3, height: 3)), with: .color(color))
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
