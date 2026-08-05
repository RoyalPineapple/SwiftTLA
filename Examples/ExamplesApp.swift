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
        ScrollView {
            VStack(spacing: 0) {
                HSplitView {
                    themeView.frame(minWidth: 300)
                    inspectorView.frame(minWidth: 250, idealWidth: 300)
                }
                if let code = codeForExample {
                    Divider().padding(.horizontal, 8)
                    ViewCodePanel(swift: code.swift, tla: code.tla).frame(height: 250)
                }
            }
        }
    }

    private var codeForExample: (swift: String, tla: String)? {
        switch id {
        case .hourClock: return (swift_hourclock, HourClock.tla)
        case .dieHard:   return (swift_diehard, DieHard.tla)
        case .coffeeCan: return (swift_coffeecan, CoffeeCan.tla)
        case .movingCat: return (swift_movingcat, MovingCat.tla)
        case .majority:  return (swift_majority, Majority.tla)
        case .sumsEven:  return (swift_sumseven, SumsEven.tla)
        case .allocator: return (swift_allocator, Allocator.tla)
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
                case .hourClock: StateMachineView(machine: HourClock.StateMachine.initial).id("hc")
                case .dieHard: StateMachineView(machine: DieHard.StateMachine.initial).id("dh")
                case .coffeeCan: StateMachineView(machine: CoffeeCan.StateMachine.initial).id("cc")
                case .movingCat: StateMachineView(machine: MovingCat.StateMachine.initial).id("mc")
                case .majority: StateMachineView(machine: Majority.StateMachine.initial).id("mj")
                case .allocator: StateMachineView(machine: Allocator.StateMachine.initial).id("al")
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

// MARK: - TLA+

extension HourClock { static var tla: String { spec.tlaModule } }
extension DieHard { static var tla: String { spec.tlaModule } }
extension CoffeeCan { static var tla: String { spec.tlaModule } }
extension MovingCat { static var tla: String { spec.tlaModule } }
extension Majority { static var tla: String { spec.tlaModule } }
extension SumsEven { static var tla: String { spec.tlaModule } }
extension Allocator { static var tla: String { spec.tlaModule } }

// MARK: - Swift DSL

let swift_hourclock = """
@TLAModel public struct HourClock {
    static var spec: TLASpec {
        TLASpec("HourClock") {
            let hr = Var<Int>("hr"); Variable(hr, 1)
            Action("HCnxt") { (hr != 12) && hr.becomes(hr + 1) || (hr == 12) && hr.becomes(1) }
            Invariant("HCini") { hr >= 1 && hr <= 12 }
        }
    }

}
"""
let swift_diehard = """
@TLAModel public struct DieHard {
    static var spec: TLASpec {
        TLASpec("DieHard") {
            Extends("Naturals"); let big = Var<Int>("big"); let small = Var<Int>("small")
            Variable(big, 0); Variable(small, 0)
            Invariant("TypeOK") { big >= 0 && big <= 5 && small >= 0 && small <= 3 }
            Action("FillSmallJug")  { small.becomes(3) && big.stays }
            Action("FillBigJug")    { big.becomes(5) && small.stays }
            Action("EmptySmallJug") { small.becomes(0) && big.stays }
            Action("EmptyBigJug")   { big.becomes(0) && small.stays }
            Action("SmallToBig") { (big+small <= 5) && big.becomes(big+small) && small.becomes(0) || (big+small > 5) && big.becomes(5) && small.becomes(small-(5-big)) }
            Action("BigToSmall") { (big+small <= 3) && small.becomes(big+small) && big.becomes(0) || (big+small > 3) && small.becomes(3) && big.becomes(big-(3-small)) }
            Invariant("NotSolved") { big != 4 }
        }
    }

}
"""
let swift_coffeecan = """
@TLAModel public struct CoffeeCan {
    static var spec: TLASpec {
        TLASpec("CoffeeCan") {
            Extends("Naturals"); let black = Var<Int>("black"); let white = Var<Int>("white")
            Variable(black, 5); Variable(white, 5)
            Action("PickSameColorBlack") { (black+white>1) && black>=2 && black.becomes(black-1) && white.stays }
            Action("PickSameColorWhite") { (black+white>1) && white>=2 && black.becomes(black+1) && white.becomes(white-2) }
            Action("PickDifferentColor") { (black+white>1) && black>=1 && white>=1 && black.becomes(black-1) && white.stays }
            Action("Termination") { (black+white==1) && black.stays && white.stays }
            DeadlockCheck()
        }
    }

}
"""
let swift_movingcat = """
@TLAModel public struct MovingCat {
    static var spec: TLASpec {
        TLASpec("MovingCat") {
            Extends("Naturals"); let cat = Var<Int>("cat"); let observed = Var<Int>("observed"); let direction = Var<Int>("direction")
            Variable(cat, 3); Variable(observed, 3); Variable(direction, 1)
            Invariant("TypeOK") { cat>=1 && cat<=6 && observed>=2 && observed<=5 && direction>=-1 && direction<=1 }
            Action("Next") { (cat<6 && cat.becomes(cat+1) || cat>1 && cat.becomes(cat-1)) && ((dir==1 && obs<5) && ...) }
        }
    }

}
"""
let swift_majority = """
@TLAModel public struct Majority {
    static var spec: TLASpec {
        TLASpec("Majority") {
            Extends("Integers"); let cand = Var<Int>("cand"); let cnt = Var<Int>("cnt"); let i = Var<Int>("i")
            Variable(cand, 0); Variable(cnt, 0); Variable(i, 1)
            Invariant("TypeOK") { i>=1 && i<=4 && cand>=1 && cand<=3 && cnt>=0 && cnt<=3 }
            Action("Next") { (i<=3) && i.becomes(i+1) && (cnt==0 && cand.becomes(i) && cnt.becomes(1) || cnt!=0 && cand==i && cand.stays && cnt.becomes(cnt+1) || cnt!=0 && cand!=i && cand.stays && cnt.becomes(cnt-1)) }
            DeadlockCheck()
        }
    }

}
"""
let swift_sumseven = """
@TLAModel public struct SumsEven {
    static var spec: TLASpec {
        TLASpec("sums_even") {
            Extends("Naturals"); let sum = Var<Int>("sum"); Variable(sum, 0)
            Action("Double") { sum.becomes(sum + 2) }
            Invariant("Even") { sum % 2 == 0 }
        }
    }

}
"""
let swift_allocator = """
@TLAModel public struct Allocator {
    static var spec: TLASpec {
        TLASpec("allocator") {
            Extends("Naturals"); let available = Var<Int>("available"); let allocated = Var<Int>("allocated")
            Variable(available, 3); Variable(allocated, 0)
            Action("Allocate")   { available.becomes(available-1).when(available>0) && allocated.becomes(allocated+1) }
            Action("Deallocate") { available.becomes(available+1).when(allocated>0) && allocated.becomes(allocated-1) }
            Invariant("ResourceCount") { available + allocated == 3 }
        }
    }

}
"""

// MARK: - Code panel view

struct ViewCodePanel: View {
    let swift: String; let tla: String
    @State private var copied = false
    var body: some View {
        HStack(spacing: 0) {
            codeCol("Swift DSL", swift)
            Divider()
            codeCol("TLA+", tla)
        }
    }
    func codeCol(_ title: String, _ code: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary).padding(.leading, 8).padding(.top, 4)
                Spacer()
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(code, forType: .string)
                    copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                }.font(.caption).buttonStyle(.plain).padding(.trailing, 8).padding(.top, 4)
            }
            ScrollView {
                Text(code).font(.system(size: 10, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }.background(.black.opacity(0.03))
        }
    }
}