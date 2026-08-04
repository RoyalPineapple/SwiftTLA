import SwiftUI
import SwiftTLA
import Examples

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
                    Label(example.name, systemImage: "square.grid.3x3")
                        .tag(example)
                }
            }
            .navigationTitle("SwiftTLA Examples")
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            if let example = selected {
                ExampleDetailView(example: example)
            }
        }
    }
}

struct ExampleDetailView: View {
    let example: ExampleDescription
    @State private var graph: StateGraph?
    @State private var stateID: StateGraph.StateID?
    @State private var history: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(example.name).font(.largeTitle).bold()
                    Text(example.about).foregroundStyle(.secondary)
                }.padding()
                Divider()

                if let graph, let sid = stateID, let state = graph.states[sid] {
                    statePanel(state: state, graph: graph, sid: sid)
                        .frame(maxWidth: .infinity).padding()
                }
                Divider()
                Text("\(graph?.states.count ?? 0) states verified")
                    .font(.caption).foregroundStyle(.secondary).padding()
            }
        }
        .toolbar { Button("Reset") { loadGraph() } }
        .onAppear { loadGraph() }
    }

    func statePanel(state: [String: TLAValue], graph: StateGraph, sid: StateGraph.StateID) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                ForEach(state.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack { Text(key).bold(); Text("= \(value)") }
                }
            }.padding().background(.quaternary).cornerRadius(8)

            let transitions = graph.transitions[sid] ?? []
            ForEach(transitions, id: \.action) { t in
                Button(t.action) { stateID = t.target; history.append(t.action) }
                    .buttonStyle(.bordered)
            }
            if !history.isEmpty {
                Text(history.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    func loadGraph() {
        if let result = try? ModelChecker(spec: example.spec, maxStates: 10000).exploreGraph() {
            graph = result
            stateID = result.states.keys.min(by: { $0.id < $1.id })
            history = []
        }
    }
}
