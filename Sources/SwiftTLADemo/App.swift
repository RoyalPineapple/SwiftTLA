import SwiftUI
import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAExamples

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
                ForEach(Examples.all) { example in
                    Label(example.name, systemImage: icon(for: example.name))
                        .tag(example)
                }
            }
            .navigationTitle("Examples")
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            if let example = selected {
                ExampleDetailView(example: example)
            }
        }
    }

    func icon(for name: String) -> String {
        let icons = [
            "HourClock": "clock",
            "DieHard": "drop",
            "CoffeeCan": "cup.and.saucer",
            "MovingCat": "cat",
            "Majority": "checkmark.circle",
        ]
        return icons[name] ?? "square.grid.3x3"
    }
}

struct ExampleDetailView: View {
    let example: ExampleDescription

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                interactiveView
                    .frame(maxWidth: .infinity)
                    .padding()
                Divider()
                SourcePanels(spec: example.spec)
            }
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(example.name)
                .font(.largeTitle)
                .bold()
            Text(example.about)
                .foregroundStyle(.secondary)
            if let url = URL(string: example.source) {
                Link("Source \u{2197}", destination: url)
                    .font(.caption)
            }
        }
        .padding()
    }

    @ViewBuilder
    var interactiveView: some View {
        switch example.name {
        case "HourClock": HourClockScreen()
        case "DieHard": DieHardScreen()
        case "CoffeeCan": CoffeeCanScreen()
        default: StateExplorer(example: example)
        }
    }
}

// MARK: - Source panels

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
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)

            ScrollView(.vertical) {
                Text(text)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary)
            .cornerRadius(4)
            .overlay(alignment: .topTrailing) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial)
                .cornerRadius(4)
                .padding(4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - State explorer (generic, works with any spec)

struct StateExplorer: View {
    let example: ExampleDescription
    @State private var graph: StateGraph?
    @State private var currentStateID: StateGraph.StateID?
    @State private var history: [String] = []

    var body: some View {
        VStack(spacing: 12) {
            if let graph, let stateID = currentStateID, let state = graph.states[stateID] {
                stateView(state)
                actionsView(graph: graph, stateID: stateID)
                if !history.isEmpty {
                    Text(history.joined(separator: " \u{2192} "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Reset") { loadGraph() }
                .buttonStyle(.bordered)
            Text("\(graph?.states.count ?? 0) states verified")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { loadGraph() }
    }

    func stateView(_ state: [String: TLAValue]) -> some View {
        VStack(spacing: 4) {
            ForEach(state.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key).bold()
                    Text("= \(value)")
                }
            }
        }
        .padding()
        .background(.quaternary)
        .cornerRadius(8)
    }

    func actionsView(graph: StateGraph, stateID: StateGraph.StateID) -> some View {
        let transitions = graph.transitions[stateID] ?? []
        return ForEach(transitions, id: \.action) { transition in
            Button(transition.action) {
                currentStateID = transition.target
                history.append(transition.action)
            }
            .buttonStyle(.bordered)
        }
    }

    func loadGraph() {
        if let result = try? ModelChecker(spec: example.spec, maxStates: 10000).exploreGraph() {
            graph = result
            currentStateID = result.states.keys.min(by: { $0.id < $1.id })
            history = []
        }
    }
}

// MARK: - Interactive screens (typed, using Machine)

struct HourClockScreen: View {
    @State private var clock = HourClock.Machine(hr: 1)

    var body: some View {
        VStack(spacing: 16) {
            Text("\(clock.hr):00")
                .font(.system(size: 72, weight: .bold, design: .monospaced))
            Button("Tick") { clock.apply(.tick) }
                .buttonStyle(.borderedProminent)
            Button("Reset") { clock = HourClock.Machine(hr: 1) }
                .buttonStyle(.bordered)
            Text("12 states verified")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct DieHardScreen: View {
    @State private var puzzle = DieHard.Machine(jug3: 0, jug5: 0)

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                JugView(label: "3 gal", level: puzzle.jug3, capacity: 3)
                JugView(label: "5 gal", level: puzzle.jug5, capacity: 5)
            }
            Text(puzzle.jug5 == 4 ? "\u{1F389} 4 gallons!" : "\(puzzle.jug5) gal")
                .font(.title)
            ForEach(puzzle.availableActions, id: \.self) { action in
                Button(action.rawValue) { puzzle.apply(action) }
                    .buttonStyle(.bordered)
            }
            Button("Reset") { puzzle = DieHard.Machine(jug3: 0, jug5: 0) }
                .buttonStyle(.bordered)
            Text("16 states verified")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct JugView: View {
    let label: String
    let level: Int
    let capacity: Int

    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .stroke()
                    .frame(width: 60, height: 120)
                Rectangle()
                    .fill(.blue.opacity(0.6))
                    .frame(width: 58, height: CGFloat(level) / CGFloat(capacity) * 118)
            }
            Text(label).font(.caption)
        }
    }
}

struct CoffeeCanScreen: View {
    @State private var can = CoffeeCan.Machine(black: 5, white: 5)

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                BeanView(label: "Black", count: can.black)
                BeanView(label: "White", count: can.white)
            }
            Text("Parity: \(can.white % 2)")
                .foregroundColor(parityPreserved ? .green : .red)
            ForEach(can.availableActions, id: \.self) { action in
                Button(action.rawValue) { can.apply(action) }
                    .buttonStyle(.bordered)
            }
            Button("Reset") { can = CoffeeCan.Machine(black: 5, white: 5) }
                .buttonStyle(.bordered)
        }
    }

    var parityPreserved: Bool { true }
}

struct BeanView: View {
    let label: String
    let count: Int

    var body: some View {
        VStack {
            Text("\(count)")
                .font(.system(size: 48, weight: .bold, design: .monospaced))
            Text(label).font(.caption)
        }
    }
}
