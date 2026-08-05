import SwiftUI
import SwiftTLA
import SwiftTLAMacros
import SwiftTLAUI

enum ExampleID: Int, CaseIterable {
    case hourClock = 0, dieHard, coffeeCan, movingCat, majority, sumsEven, allocator
}

@TLAModel
struct AppNavigation {
    static var spec: TLASpec {
        TLASpec("AppNavigation") {
            let screen = Var<Int>("screen")
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
                        var copy = nav
                        switch id {
                        case .hourClock: copy.apply(.selectHourClock)
                        case .dieHard: copy.apply(.selectDieHard)
                        case .coffeeCan: copy.apply(.selectCoffeeCan)
                        case .movingCat: copy.apply(.selectMovingCat)
                        case .majority: copy.apply(.selectMajority)
                        case .sumsEven: copy.apply(.selectSumsEven)
                        case .allocator: copy.apply(.selectAllocator)
                        }
                        nav = copy
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(nav.screen == id.rawValue ? .primary : .secondary)
                    .fontWeight(nav.screen == id.rawValue ? .bold : .regular)
                }
                .navigationTitle("Examples")
            } detail: {
                ExamplePage(id: ExampleID(rawValue: nav.screen) ?? .hourClock)
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
            switch id {
            case .hourClock: StateMachineView(machine: HourClock.Machine.initial).id("hc")
            case .dieHard: StateMachineView(machine: DieHard.Machine.initial).id("dh")
            case .coffeeCan: StateMachineView(machine: CoffeeCan.Machine.initial).id("cc")
            case .movingCat: StateMachineView(machine: MovingCat.Machine.initial).id("mc")
            case .majority: StateMachineView(machine: Majority.Machine.initial).id("mj")
            case .sumsEven: EmptyView()
            case .allocator: StateMachineView(machine: Allocator.Machine.initial).id("al")
            }
        }
        .background(.regularMaterial)
    }
}

private let examples: [ExampleID: ExampleDescription] = Dictionary(
    uniqueKeysWithValues: zip(ExampleID.allCases, Examples.all)
)