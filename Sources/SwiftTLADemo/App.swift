import SwiftUI
import SwiftTLA
import SwiftTLAExamples

@main
struct DemoApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                ClockView().tabItem { Text("HourClock") }
                DieHardView().tabItem { Text("DieHard") }
                CoffeeCanView().tabItem { Text("CoffeeCan") }
            }
        }
    }
}

// MARK: - HourClock

struct ClockView: View {
    @State private var clock = HourClock(hr: 1)
    @State private var history: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("\(clock.hr):00")
                .font(.system(size: 72, weight: .bold, design: .monospaced))
            
            Button("Tick") {
                clock.apply(.tick)
                if clock.hr == 1 && !history.isEmpty { history = [] }
                history.append("tick")
            }
            .buttonStyle(.borderedProminent)
            .font(.title)
            
            if !history.isEmpty {
                Text("Ticks: \(history.count)")
                    .foregroundStyle(.secondary)
            }
            
            Button("Reset") { clock = HourClock(hr: 1); history = [] }
            TLAView(spec: HourClockSpec.spec, name: "HourClock")
            StatesView(states: 12)
        }
        .padding()
    }
}

// MARK: - DieHard

struct DieHardView: View {
    @State private var puzzle = DieHard(jug3: 0, jug5: 0)
    @State private var history: [String] = []
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                JugView(label: "3 gal", level: puzzle.jug3, capacity: 3)
                JugView(label: "5 gal", level: puzzle.jug5, capacity: 5)
            }
            
            Text(puzzle.jug5 == 4 ? "🎉 Found 4 gallons!" : "\(puzzle.jug5) / 5")
                .font(.title)
            
            Text("Actions").font(.headline)
            ForEach(puzzle.availableActions, id: \.self) { action in
                Button(action.rawValue) {
                    puzzle.apply(action)
                    history.append(action.rawValue)
                }
                .buttonStyle(.bordered)
            }
            
            Button("Reset") { puzzle = DieHard(jug3: 0, jug5: 0); history = [] }
            TLAView(spec: DieHardSpec.spec, name: "DieHard")
            StatesView(states: 16)
        }
        .padding()
    }
}

struct JugView: View {
    let label: String; let level: Int; let capacity: Int
    var body: some View {
        VStack {
            ZStack(alignment: .bottom) {
                Rectangle().stroke().frame(width: 60, height: 120)
                Rectangle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 58, height: CGFloat(level) / CGFloat(capacity) * 118)
            }
            Text(label).font(.caption)
        }
    }
}

// MARK: - CoffeeCan

struct CoffeeCanView: View {
    @State private var can = CoffeeCan(black: 5, white: 5)
    @State private var history: [String] = []
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                BeanCounter(label: "Black", count: can.black)
                BeanCounter(label: "White", count: can.white)
            }
            
            Text("Parity: \(can.white % 2)")
            Text(can.parityPreserved ? "✓ Preserved" : "✗ Violated")
                .foregroundColor(can.parityPreserved ? .green : .red)
            
            Text("Actions").font(.headline)
            ForEach(can.availableActions, id: \.self) { action in
                Button(action.rawValue) {
                    can.apply(action)
                    history.append(action.rawValue)
                }
                .buttonStyle(.bordered)
            }
            
            Button("Reset") { can = CoffeeCan(black: 5, white: 5); history = [] }
            TLAView(spec: CoffeeCanSpec.spec, name: "CoffeeCan")
        }
        .padding()
    }
}

struct BeanCounter: View {
    let label: String; let count: Int
    var body: some View {
        VStack {
            Text("\(count)").font(.system(size: 48, weight: .bold, design: .monospaced))
            Text(label).font(.caption)
        }
    }
}

// MARK: - Shared

struct TLAView: View {
    let spec: TLASpec
    let name: String
    @State private var show = false
    
    var body: some View {
        HStack {
            Button("View TLA+") { show = true }
            Button("Export .tla") { export() }
        }
        .sheet(isPresented: $show) {
            ScrollView {
                Text(spec.description)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
            }
            .frame(minWidth: 500, minHeight: 400)
        }
    }
    
    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).tla"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? spec.description.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct StatesView: View {
    let states: Int
    var body: some View {
        Text("\(states) reachable states (verified)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
