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
                        var path = Path()
                        path.move(to: CGPoint(x: a.x * z, y: a.y * z))
                        path.addLine(to: CGPoint(x: b.x * z, y: b.y * z))
                        context.stroke(path, with: .color(.white.opacity(0.18)), lineWidth: 1)
                    }
                }
                ForEach(graph.nodes) { node in
                    bubble(node)
                        .position(spots[node.id].map { CGPoint(x: $0.x * z, y: $0.y * z) } ?? CGPoint(x: side * z / 2, y: side * z / 2))
                        .opacity(matches(node) ? 1 : 0.2)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 4).onChanged { spots[node.id] = CGPoint(x: $0.location.x / z, y: $0.location.y / z) }
                        )
                        .onTapGesture { open = OpenNode(id: node.id) }
                }
            }
            .frame(width: side * z, height: side * z)
        }
        .defaultScrollAnchor(.center)
        // Pinch to zoom, from a quarter size (the whole web) to 2.5×.
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let start = pinchStart ?? zoom
                    pinchStart = start
                    zoom = min(2.5, max(0.25, start * value.magnification))
                }
                .onEnded { _ in pinchStart = nil }
        )
        .onAppear {
            if spots.isEmpty {
                spots = MemoryLayout.place(graph, side: side - 80).mapValues { CGPoint(x: $0.x + 40, y: $0.y + 40) }
            }
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
