import SwiftUI
import SwiftTLA
import SwiftTLAUI

enum ExampleID: Int, CaseIterable {
    case hourClock = 0, dieHard, coffeeCan, movingCat, majority, sumsEven, allocator
}

@main
struct ExamplesApp: App {
    @State private var selected: ExampleID = .hourClock

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(ExampleID.allCases, id: \.self) { id in
                    Button(examples[id]!.name) {
                        selected = id
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected == id ? .primary : .secondary)
                    .fontWeight(selected == id ? .bold : .regular)
                }
                .navigationTitle("Examples")
            } detail: {
                ExamplePage(id: selected)
            }
        }
    }
}

struct ExamplePage: View {
    let id: ExampleID

    var body: some View {
        HSplitView {
            themeView.frame(minWidth: 300)
            inspectorView.frame(minWidth: 250, idealWidth: 300)
        }
    }

    @ViewBuilder
    private var themeView: some View {
        switch id {
        case .hourClock: HourClockThemeView()
        case .dieHard: DieHardThemeView()
        case .coffeeCan: CoffeeCanThemeView()
        case .movingCat: MovingCatThemeView()
        case .majority: MajorityThemeView()
        case .sumsEven: SumsEvenThemeView()
        case .allocator: AllocatorThemeView()
        }
    }

    @ViewBuilder
    private var inspectorView: some View {
        VStack {
            Text("Inspector").font(.headline).padding(.top, 8)
            Divider()
            if id != .sumsEven {
                switch id {
                case .hourClock: StateMachineView(machine: HourClock.Machine.initial).id("hc")
                case .dieHard: StateMachineView(machine: DieHard.Machine.initial).id("dh")
                case .coffeeCan: StateMachineView(machine: CoffeeCan.Machine.initial).id("cc")
                case .movingCat: StateMachineView(machine: MovingCat.Machine.initial).id("mc")
                case .majority: StateMachineView(machine: Majority.Machine.initial).id("mj")
                case .allocator: StateMachineView(machine: Allocator.Machine.initial).id("al")
                default: EmptyView()
                }
            }
        }
        .background(.regularMaterial)
    }
}

private let examples: [ExampleID: ExampleDescription] = Dictionary(
    uniqueKeysWithValues: zip(ExampleID.allCases, Examples.all)
)