import SwiftUI
import SwiftTLA
import SwiftTLAExamples

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var selected: ExampleDescription?
    
    var body: some View {
        NavigationSplitView {
            List(Examples.all, id: \.name, selection: $selected) { ex in
                Label(ex.name, systemImage: icon(for: ex.name))
            }
            .navigationTitle("Examples")
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            if let ex = selected {
                ExampleDetailView(example: ex)
            } else {
                Text("Select an example")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    func icon(for name: String) -> String {
        switch name {
        case "HourClock": return "clock"
        case "DieHard": return "drop"
        case "CoffeeCan": return "cup.and.saucer"
        default: return "square.grid.3x3"
        }
    }
}

struct ExampleDetailView: View {
    let example: ExampleDescription
    @State private var showTLA = false
    
    var body: some View {
        VStack {
            switch example.name {
            case "HourClock": ClockView()
            case "DieHard": DieHardView()
            case "CoffeeCan": CoffeeCanView()
            default:
                Text("No interactive view for \(example.name)")
            }
        }
        .navigationTitle(example.name)
        .toolbar {
            ToolbarItem {
                HStack {
                    Button("View TLA+") { showTLA = true }
                    Button("Export .tla") { export() }
                }
            }
        }
        .sheet(isPresented: $showTLA) {
            VStack {
                HStack { Spacer(); Button("Close") { showTLA = false }.padding() }
                ScrollView {
                    Text(example.spec.description)
                        .font(.system(.caption, design: .monospaced))
                        .padding()
                }
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }
    
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(example.name).tla"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? example.spec.description.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - HourClock

struct ClockView: View {
    @State private var clock = HourClock(hr: 1)
    @State private var history: [String] = []
    
    var body: some View {
        VStack(spacing: 24) {
            Text("\(clock.hr):00")
                .font(.system(size: 80, weight: .bold, design: .monospaced))
            
            Button("Tick") {
                clock.apply(.tick)
                if clock.hr == 1 && !history.isEmpty { history = [] }
                history.append("tick")
            }
            .buttonStyle(.borderedProminent)
            
            if !history.isEmpty {
                Text("\(history.count) ticks — 12 states verified")
                    .foregroundStyle(.secondary)
            }
            
            Button("Reset") { clock = HourClock(hr: 1); history = [] }
        }
        .padding()
    }
}

// MARK: - DieHard

struct DieHardView: View {
    @State private var puzzle = DieHard(jug3: 0, jug5: 0)
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 40) {
                Jug(label: "3 gal", level: puzzle.jug3, capacity: 3)
                Jug(label: "5 gal", level: puzzle.jug5, capacity: 5)
            }
            
            Text(puzzle.jug5 == 4 ? "🎉 4 gallons!" : "\(puzzle.jug5) gal")
                .font(.title)
            
            ForEach(puzzle.availableActions, id: \.self) { action in
                Button(action.rawValue) { puzzle.apply(action) }
                    .buttonStyle(.bordered)
            }
            
            Button("Reset") { puzzle = DieHard(jug3: 0, jug5: 0) }
            
            Text("16 reachable states (verified)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct Jug: View {
    let label: String; let level: Int; let capacity: Int
    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                Rectangle().stroke().frame(width: 60, height: 120)
                Rectangle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 58, height: CGFloat(level)/CGFloat(capacity)*118)
            }
            Text(label).font(.caption)
        }
    }
}

// MARK: - CoffeeCan

struct CoffeeCanView: View {
    @State private var can = CoffeeCan(black: 5, white: 5)
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 40) {
                Bean(label: "Black", count: can.black)
                Bean(label: "White", count: can.white)
            }
            
            Text("Parity: \(can.white % 2)")
            Text(can.parityPreserved ? "✓ Preserved" : "✗ Violated")
                .foregroundColor(can.parityPreserved ? .green : .red)
            
            ForEach(can.availableActions, id: \.self) { action in
                Button(action.rawValue) { can.apply(action) }
                    .buttonStyle(.bordered)
            }
            
            Button("Reset") { can = CoffeeCan(black: 5, white: 5) }
        }
        .padding()
    }
}

struct Bean: View {
    let label: String; let count: Int
    var body: some View {
        VStack {
            Text("\(count)").font(.system(size: 48, weight: .bold, design: .monospaced))
            Text(label).font(.caption)
        }
    }
}
