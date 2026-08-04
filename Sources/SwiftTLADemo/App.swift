import SwiftUI
import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAExamples

struct ExampleDescription: Hashable, Identifiable {
    var id: String { name }
    let name: String; let spec: TLASpec; let expectedStates: Int
    let source: String; let about: String
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
    static func == (a: ExampleDescription, b: ExampleDescription) -> Bool { a.name == b.name }
}

let allExamples: [ExampleDescription] = [
    .init(name: "HourClock", spec: HourClock.spec, expectedStates: 12, source: "https://lamport.azurewebsites.net/tla/book.html", about: "A clock that ticks from 1 to 12 and wraps."),
    .init(name: "DieHard", spec: DieHard.spec, expectedStates: 16, source: "https://github.com/tlaplus/Examples/tree/master/specifications/DieHard", about: "Measure exactly 4 gallons using 3 and 5 gallon jugs."),
    .init(name: "CoffeeCan", spec: CoffeeCan.spec, expectedStates: 0, source: "https://github.com/tlaplus/Examples/tree/master/specifications/CoffeeCan", about: "Remove beans from a can."),
    .init(name: "MovingCat", spec: MovingCat.spec, expectedStates: 24, source: "https://github.com/tlaplus/Examples/tree/master/specifications/Moving_Cat_Puzzle", about: "A cat bounces between boxes."),
    .init(name: "Majority", spec: Majority.spec, expectedStates: 0, source: "https://github.com/tlaplus/Examples/tree/master/specifications/Majority", about: "Boyer-Moore majority vote."),
    .init(name: "BoundedCounter", spec: BoundedCounter.spec, expectedStates: 7, source: "internal", about: "A counter that stays within bounds."),
    .init(name: "Toggle", spec: Toggle.spec, expectedStates: 2, source: "internal", about: "A simple on/off toggle."),
    .init(name: "BoolToggle", spec: BoolToggle.spec, expectedStates: 2, source: "internal", about: "A boolean toggle."),
    .init(name: "ThreeState", spec: ThreeState.spec, expectedStates: 3, source: "internal", about: "A three-state loop."),
    .init(name: "Bridge", spec: Bridge.spec, expectedStates: 12, source: "internal", about: "A single-lane bridge."),
    .init(name: "Lock", spec: Lock.spec, expectedStates: 2, source: "internal", about: "A binary lock."),
    .init(name: "Fibonacci", spec: Fibonacci.spec, expectedStates: 5, source: "internal", about: "Fibonacci sequence."),
    .init(name: "PingPong", spec: PingPong.spec, expectedStates: 2, source: "internal", about: "Ping pong."),
    .init(name: "Database", spec: Database.spec, expectedStates: 0, source: "internal", about: "Write-lock-unlock cycle."),
    .init(name: "Elevator", spec: Elevator.spec, expectedStates: 5, source: "internal", about: "An elevator moving between floors."),
    .init(name: "Traffic", spec: Traffic.spec, expectedStates: 3, source: "internal", about: "A traffic light."),
    .init(name: "Buffer", spec: Buffer.spec, expectedStates: 2, source: "internal", about: "A single-slot buffer."),
]

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var selected: ExampleDescription?

    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(allExamples) { example in
                    Label(example.name, systemImage: "square.grid.3x3").tag(example)
                }
            }
            .navigationTitle("Examples")
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            if let example = selected {
                ExampleDetail(example: example)
            }
        }
    }
}

struct ExampleDetail: View {
    let example: ExampleDescription

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.name).font(.largeTitle).bold()
                    Text(example.about).foregroundStyle(.secondary)
                    if let url = URL(string: example.source) {
                        Link("Source \u{2197}", destination: url).font(.caption)
                    }
                }.padding()
                Divider()
                StateExplorer(example: example).frame(maxWidth: .infinity).padding()
                Divider()
                SourcePanels(spec: example.spec)
            }
        }
    }
}

struct SourcePanels: View {
    let spec: TLASpec
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            CodePanel(title: "@TLAModel", text: spec.annotatedForm)
            Spacer().frame(width: 25)
            CodePanel(title: "TLA+", text: spec.tlaModule)
        }
    }
}

struct CodePanel: View {
    let title: String; let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 8)
            ScrollView(.vertical) {
                Text(text).font(.system(size: 10, design: .monospaced)).padding(8).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary).cornerRadius(4)
            .overlay(alignment: .topTrailing) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption2).padding(6)
                }.buttonStyle(.plain).background(.regularMaterial).cornerRadius(4).padding(4)
            }
        }.frame(maxWidth: .infinity)
    }
}

struct StateExplorer: View {
    let example: ExampleDescription
    @State private var graph: StateGraph?
    @State private var currentStateID: StateGraph.StateID?
    @State private var history: [String] = []

    var body: some View {
        VStack(spacing: 12) {
            if let graph, let stateID = currentStateID, let state = graph.states[stateID] {
                VStack(spacing: 4) {
                    ForEach(state.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack { Text(key).bold(); Text("= \(value)") }
                    }
                }.padding().background(.quaternary).cornerRadius(8)

                let transitions = graph.transitions[stateID] ?? []
                ForEach(transitions, id: \.action) { transition in
                    Button(transition.action) {
                        currentStateID = transition.target
                        history.append(transition.action)
                    }.buttonStyle(.bordered)
                }
                if !history.isEmpty {
                    Text(history.joined(separator: " \u{2192} ")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Reset") { loadGraph() }.buttonStyle(.bordered)
            Text("\(graph?.states.count ?? 0) states verified").font(.caption).foregroundStyle(.secondary)
        }.padding().onAppear { loadGraph() }
    }

    func loadGraph() {
        if let result = try? ModelChecker(spec: example.spec, maxStates: 10000).exploreGraph() {
            graph = result
            currentStateID = result.states.keys.min(by: { $0.id < $1.id })
            history = []
        }
    }
}
