// Memory (Dylan, 2026-11-26): what Jarvis remembers, as a web of bubbles
// you can drag, or a plain list; a tap opens that bubble's facts, each with
// Forget. Kept lean on purpose: one call for the web, one per bubble.
import AVFoundation
import SwiftUI
import JarvisKit

struct MemoryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var graph: MemoryGraph?
    @State private var loading = true
    @State private var problem: String?
    @State private var spots: [String: CGPoint] = [:]
    @State private var open: OpenNode?
    @State private var query = ""
    @State private var asList = false
    /// Pinch zoom on the web (Dylan, 2026-11-26), and where the pinch started.
    @State private var zoom: CGFloat = 1
    @State private var pinchStart: CGFloat?
    /// The bubble being dragged: it lifts, its lines light, its neighbours follow.
    @State private var dragging: String?

    /// The bubble whose sheet is open.
    struct OpenNode: Identifiable { let id: String }

    var body: some View {
        Group {
            if loading {
                ProgressView("Loading memory…")
            } else if let graph, !graph.nodes.isEmpty {
                if asList { list(graph) } else { web(graph) }
            } else {
                Text(problem ?? "Jarvis hasn't shared his memory web yet.")
                    .foregroundStyle(Theme.frostDim).multilineTextAlignment(.center).padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.sky.ignoresSafeArea())
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search memory")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("View", selection: $asList) {
                    Image(systemName: "circle.hexagongrid").tag(false).accessibilityLabel("Web")
                    Image(systemName: "list.bullet").tag(true).accessibilityLabel("List")
                }
                .pickerStyle(.segmented)
            }
        }
        .sheet(item: $open) { MemoryNodeSheet(id: $0.id).environmentObject(app) }
        .task { await load() }
    }

    private func load() async {
        do {
            graph = try await app.client.memoryGraph()
        } catch {
            problem = error.localizedDescription
        }
        loading = false
    }

    private func matches(_ node: MemoryGraph.Node) -> Bool {
        query.isEmpty || node.name.localizedCaseInsensitiveContains(query)
    }

    /// Bubbles and lines on a canvas bigger than the screen; scroll to roam,
    /// drag a bubble to move it.
    private func web(_ graph: MemoryGraph) -> some View {
        let side = max(700, Double(graph.nodes.count).squareRoot() * 110)
        // Spots are kept unzoomed; drawing scales them, drags scale back.
        let z = zoom
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for link in graph.links {
                        guard let a = spots[link.from], let b = spots[link.to] else { continue }
                        let lit = dragging != nil && (link.from == dragging || link.to == dragging)
                        var path = Path()
                        path.move(to: CGPoint(x: a.x * z, y: a.y * z))
                        path.addLine(to: CGPoint(x: b.x * z, y: b.y * z))
                        context.stroke(path, with: .color(.white.opacity(lit ? 0.6 : 0.18)), lineWidth: lit ? 2 : 1)
                    }
                }
                .contentShape(Rectangle())
                // Double-tap the empty space: in a step, or back out once close.
                .onTapGesture(count: 2) { setZoom(zoom >= 2 ? fitZoom(side) : zoom * 1.6) }
                ForEach(graph.nodes) { node in
                    bubble(node)
                        .scaleEffect(dragging == node.id ? 1.25 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: dragging == node.id)
                        .position(spots[node.id].map { CGPoint(x: $0.x * z, y: $0.y * z) } ?? CGPoint(x: side * z / 2, y: side * z / 2))
                        .opacity(matches(node) ? 1 : 0.2)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { drag($0, node.id, graph: graph, zoom: z) }
                                .onEnded { _ in dragging = nil }
                        )
                        .onTapGesture { open = OpenNode(id: node.id) }
                }
            }
            .frame(width: side * z, height: side * z)
        }
        .defaultScrollAnchor(.center)
        .modifier(KeepCentreWhileZooming(zoom: zoom))
        .overlay(alignment: .bottomTrailing) { zoomControls(side) }
        // Pinch to zoom, from a quarter size (the whole web) to 2.5×.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? zoom
                    pinchStart = start
                    zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, start * value.magnification))
                }
                .onEnded { _ in pinchStart = nil }
        )
        .onAppear {
            if spots.isEmpty {
                spots = MemoryLayout.place(graph, side: side - 80).mapValues { CGPoint(x: $0.x + 40, y: $0.y + 40) }
            }
        }
    }

    /// The zoom limits: a quarter size (the whole web) to 2.5×.
    private static let zoomRange: ClosedRange<CGFloat> = 0.25...2.5

    private func setZoom(_ value: CGFloat) {
        Haptics.play(.tab)
        withAnimation(.smooth(duration: 0.3)) {
            zoom = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, value))
        }
    }

    /// The zoom that fits the whole web on screen.
    private func fitZoom(_ side: Double) -> CGFloat {
        let screen = UIScreen.main.bounds
        return min(1, max(Self.zoomRange.lowerBound, min(screen.width, screen.height - 160) / side))
    }

    /// − / the zoom (tap: fit the whole web) / +, for when pinching is
    /// awkward (Dylan, 2026-11-27: "allow me to zoom in and out").
    private func zoomControls(_ side: Double) -> some View {
        HStack(spacing: 0) {
            Button { setZoom(zoom / 1.4) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                .disabled(zoom <= Self.zoomRange.lowerBound)
                .accessibilityLabel("Zoom out")
            Button { setZoom(fitZoom(side)) } label: {
                Text("\(Int((zoom * 100).rounded()))%").font(.footnote.weight(.semibold)).monospacedDigit()
                    .frame(minWidth: 52, minHeight: 44)
            }
            .accessibilityLabel("Fit the whole web")
            Button { setZoom(zoom * 1.4) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                .disabled(zoom >= Self.zoomRange.upperBound)
                .accessibilityLabel("Zoom in")
        }
        .foregroundStyle(Theme.frost)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(16)
    }

    /// Moves the dragged bubble under the finger and pulls its direct
    /// neighbours a third of the way along, so the web feels alive.
    private func drag(_ value: DragGesture.Value, _ id: String, graph: MemoryGraph, zoom: CGFloat) {
        if dragging != id {
            dragging = id
            Haptics.play(.tab)
        }
        let to = CGPoint(x: value.location.x / zoom, y: value.location.y / zoom)
        guard let from = spots[id] else { spots[id] = to; return }
        let dx = to.x - from.x, dy = to.y - from.y
        spots[id] = to
        for link in graph.links where link.from == id || link.to == id {
            let other = link.from == id ? link.to : link.from
            if other == "dylan" { continue } // the centre stays put
            if let at = spots[other] { spots[other] = CGPoint(x: at.x + dx * 0.33, y: at.y + dy * 0.33) }
        }
    }

    /// A bubble sized by how much he knows, coloured by kind, name below.
    private func bubble(_ node: MemoryGraph.Node) -> some View {
        let size = CGFloat(28 + min(32, node.links * 6 + node.facts * 2))
        return VStack(spacing: 3) {
            Circle().fill(Self.color(node.type).opacity(0.85)).frame(width: size, height: size)
            Text(node.name).font(.caption2).foregroundStyle(Theme.frost).lineLimit(1).fixedSize()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func list(_ graph: MemoryGraph) -> some View {
        List(graph.nodes.filter(matches).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }) { node in
            Button { open = OpenNode(id: node.id) } label: {
                HStack {
                    Circle().fill(Self.color(node.type)).frame(width: 10, height: 10)
                    Text(node.name).foregroundStyle(Theme.frost)
                    Spacer()
                    Text("\(node.facts)").foregroundStyle(Theme.frostDim).monospacedDigit()
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    static func color(_ type: String) -> Color {
        switch type {
        case "person": return Theme.glacier
        case "place": return Theme.moss
        case "project": return Theme.ember
        case "routine": return Color(red: 0.78, green: 0.65, blue: 0.94)
        case "preference": return Theme.rose
        case "plan": return Color(red: 0.96, green: 0.84, blue: 0.43)
        case "loop": return Color(red: 1.0, green: 0.56, blue: 0.20)
        default: return Color(white: 0.66)
        }
    }
}

/// Zooming keeps the middle of what you're looking at in the middle,
/// instead of the web sliding off towards its top-left corner.
private struct KeepCentreWhileZooming: ViewModifier {
    let zoom: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.modifier(Anchored(zoom: zoom))
        } else {
            content
        }
    }

    @available(iOS 18, *)
    private struct Anchored: ViewModifier {
        let zoom: CGFloat
        @State private var position = ScrollPosition()
        @State private var visible: CGRect = .zero

        func body(content: Content) -> some View {
            content
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in visible = rect }
                .onChange(of: zoom) { old, new in
                    guard old > 0, visible.width > 0 else { return }
                    let k = new / old
                    position.scrollTo(point: CGPoint(
                        x: max(0, visible.midX * k - visible.width / 2),
                        y: max(0, visible.midY * k - visible.height / 2)))
                }
        }
    }
}

/// One bubble: its facts (swipe to Forget), open loops, and what it links to.
struct MemoryNodeSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var id: String
    @State private var node: MemoryNode?
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                if let node {
                    Section {
                        ForEach(node.facts) { fact in
                            Text(fact.text)
                                .swipeActions {
                                    Button("Forget", role: .destructive) { Task { await forget(fact) } }
                                }
                        }
                    } header: { Text("\(node.type.capitalized) · \(node.facts.count) facts") }
                    if !node.loops.isEmpty {
                        Section("Open loops") {
                            ForEach(node.loops, id: \.text) { loop in Text(loop.text) }
                        }
                    }
                    if !node.links.isEmpty {
                        Section("Linked") {
                            ForEach(node.links) { other in
                                Button { id = other.id } label: {
                                    HStack {
                                        Text(other.name).foregroundStyle(Theme.frost)
                                        Spacer()
                                        if let kind = other.kind { Text(kind).foregroundStyle(Theme.frostDim) }
                                    }
                                }
                            }
                        }
                    }
                } else if let problem {
                    Text(problem).foregroundStyle(Theme.rose)
                } else {
                    ProgressView("Loading…")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.sky.ignoresSafeArea())
            .navigationTitle(node?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { SheetClose { dismiss() } }
            .task(id: id) { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        node = nil
        problem = nil
        do { node = try await app.client.memoryNode(id) } catch { problem = error.localizedDescription }
    }

    private func forget(_ fact: MemoryNode.Fact) async {
        do {
            try await app.client.forgetFact(fact.id)
            Haptics.play(.runOK)
            await load()
        } catch {
            problem = error.localizedDescription
            Haptics.play(.runFailed)
        }
    }
}

/// Settings' Voice section: pick Kokoro's voice and speed, hear it, save.
struct VoiceSection: View {
    @EnvironmentObject private var app: AppModel
    @State private var settings: VoiceSettings?
    @State private var saved: VoiceSettings?
    @State private var busy: String?
    @State private var problem: String?
    @State private var player: AVAudioPlayerBox?

    var body: some View {
        Section {
            if let binding = Binding($settings) {
                Picker("Voice", selection: binding.voice) {
                    ForEach(binding.wrappedValue.voices) { option in
                        Text("\(option.name) (\(option.kind))").tag(option.id)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Speed \(binding.wrappedValue.speed, specifier: "%.2f")×")
                    Slider(value: binding.speed, in: 0.7...1.4, step: 0.05)
                }
                HStack {
                    Button("Play") { Task { await play() } }.buttonStyle(.borderless)
                    Spacer()
                    if let busy {
                        ProgressView().accessibilityLabel(busy)
                    } else {
                        Button("Save") { Task { await save() } }
                            .buttonStyle(.borderless)
                            .disabled(settings == saved)
                    }
                }
            } else if let problem {
                Text(problem).foregroundStyle(Theme.rose)
            } else {
                ProgressView("Loading voice…")
            }
            if settings != nil, let problem { Text(problem).font(.footnote).foregroundStyle(Theme.rose) }
        } header: {
            Text("Voice")
        } footer: {
            Text("How Jarvis sounds when he talks back. Saved on the PC; he uses it from his next reply.")
        }
        .task {
            do {
                settings = try await app.client.voiceSettings()
                saved = settings
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func play() async {
        guard let settings else { return }
        busy = "Getting a sample"
        problem = nil
        do {
            player = try AVAudioPlayerBox(data: try await app.client.voiceSample(settings))
        } catch {
            problem = error.localizedDescription
        }
        busy = nil
    }

    private func save() async {
        guard let settings else { return }
        busy = "Saving"
        problem = nil
        do {
            try await app.client.saveVoice(settings)
            saved = settings
            Haptics.play(.runOK)
        } catch {
            problem = error.localizedDescription
            Haptics.play(.runFailed)
        }
        busy = nil
    }
}

/// Holds the sample's player so it keeps playing after the call returns.
final class AVAudioPlayerBox {
    private let player: AVAudioPlayer
    init(data: Data) throws {
        player = try AVAudioPlayer(data: data)
        player.play()
    }
}
