import SwiftUI
import SwiftTLA
import SwiftTLAMacros
import SwiftTLAUI

enum ExampleID: Int, CaseIterable {
    case hourClock = 0
    case dieHard
    case coffeeCan
    case movingCat
    case majority
    case sumsEven
    case allocator
}

@TLAModel
struct AppNavigation {
    static var spec: TLASpec {
        TLASpec("AppNavigation") {
            let screen = Var("screen", value: 0)
            Variable(screen, 0)
            Action("selectHourClock") { screen.becomes(ExampleID.hourClock.rawValue) }
            Action("selectDieHard")   { screen.becomes(ExampleID.dieHard.rawValue) }
            Action("selectCoffeeCan") { screen.becomes(ExampleID.coffeeCan.rawValue) }
            Action("selectMovingCat") { screen.becomes(ExampleID.movingCat.rawValue) }
            Action("selectMajority")  { screen.becomes(ExampleID.majority.rawValue) }
            Action("selectSumsEven")  { screen.becomes(ExampleID.sumsEven.rawValue) }
            Action("selectAllocator") { screen.becomes(ExampleID.allocator.rawValue) }
            Invariant("validScreen") { screen >= 0 && screen < ExampleID.allCases.count }
        }
    }
}

@main
struct ExamplesApp: App {
    @State private var nav = AppNavigation.Machine.initial

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(ExampleID.allCases, id: \.self) { id in
                    Button(examples[id]!.name) {
                        switch id {
                        case .hourClock:  nav.apply(.selectHourClock)
                        case .dieHard:    nav.apply(.selectDieHard)
                        case .coffeeCan:  nav.apply(.selectCoffeeCan)
                        case .movingCat:  nav.apply(.selectMovingCat)
                        case .majority:   nav.apply(.selectMajority)
                        case .sumsEven:   nav.apply(.selectSumsEven)
                        case .allocator:  nav.apply(.selectAllocator)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(nav.screen == id.rawValue ? .primary : .secondary)
                    .fontWeight(nav.screen == id.rawValue ? .bold : .regular)
                }
                .navigationTitle("Examples")
            } detail: {
                if let id = ExampleID(rawValue: nav.screen), let ex = examples[id] {
                    ExampleDetailView(example: ex)
                }
            }
        }
    }
}

private let examples: [ExampleID: ExampleDescription] = Dictionary(
    uniqueKeysWithValues: zip(ExampleID.allCases, Examples.all)
)

struct ExampleDetailView: View {
    let example: ExampleDescription

    var body: some View {
        VStack(spacing: 16) {
            Text(example.name).font(.largeTitle.bold())
            Text(example.about).foregroundStyle(.secondary)
            Divider()
            exampleView
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var exampleView: some View {
        switch example.name {
        case "HourClock":  StateMachineView(machine: HourClock.Machine.initial).id("HourClock")
        case "DieHard":    StateMachineView(machine: DieHard.Machine.initial).id("DieHard")
        case "CoffeeCan":  StateMachineView(machine: CoffeeCan.Machine.initial).id("CoffeeCan")
        case "MovingCat":  StateMachineView(machine: MovingCat.Machine.initial).id("MovingCat")
        case "Majority":   StateMachineView(machine: Majority.Machine.initial).id("Majority")
        case "SumsEven":   SumsEvenProofView()
        case "Allocator":  StateMachineView(machine: Allocator.Machine.initial).id("Allocator")
        default: Text("Unknown")
        }
    }
}

struct SumsEvenProofView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "function").font(.largeTitle)
            Text("∀ x ∈ Nat : Even(x + x)")
                .font(.title.monospaced())
            Text("A TLA+ proof, not a state machine")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
