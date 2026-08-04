import SwiftUI
import SwiftTLA
import SwiftTLAGeneration
import Examples

@main
struct ExamplesApp: App {
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
            .navigationTitle("SwiftTLA")
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
    @State private var graph: StateGraph?
    @State private var stateID: StateGraph.StateID?
    @State private var history: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                liveView.frame(maxWidth: .infinity).padding()
                Divider()
                SourcePanels(spec: example.spec)
                Divider()
                footer
            }
        }
        .onAppear { loadGraph() }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(example.name).font(.largeTitle).bold()
            Text(example.about).foregroundStyle(.secondary)
            if let url = URL(string: example.source) {
                Link("Source", destination: url).font(.caption)
            }
        }.padding()
    }

    var liveView: some View {
        VStack(spacing: 12) {
            if let graph, let sid = stateID, let state = graph.states[sid] {
                statePanel(state: state, graph: graph, sid: sid)
            } else {
                ProgressView()
            }
            HStack {
                Button("Reset") { loadGraph() }
                Text("\(graph?.states.count ?? 0) states verified")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
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
                Text(history.joined(separator: " \u{2192} "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var footer: some View {
        HStack {
            Spacer()
            Text("Verified with SwiftTLA")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding()
    }

    func loadGraph() {
        graph = try? ModelChecker(spec: example.spec, maxStates: 10000).exploreGraph()
        stateID = graph.flatMap { $0.states.keys.min(by: { $0.id < $1.id }) }
        history = []
    }
}

struct SourcePanels: View {
    let spec: TLASpec
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("@TLAModel").tag(0)
                Text("TLA+").tag(1)
            }.pickerStyle(.segmented).padding(8)

            ScrollView(.vertical) {
                Text(tab == 0 ? spec.annotatedForm : spec.tlaModule)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary).cornerRadius(4)
            .overlay(alignment: .topTrailing) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tab == 0 ? spec.annotatedForm : spec.tlaModule, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption2).padding(6)
                }.buttonStyle(.plain).background(.regularMaterial).cornerRadius(4).padding(4)
            }
        }
    }
}
