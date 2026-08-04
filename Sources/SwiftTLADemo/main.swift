import SwiftTLA
import SwiftTLAExamples
import SwiftTLAMacros

// #TLASpec — write TLA+ specs in Swift, checked at compile time
let hr = Var<Int>("hr")

#TLASpec {
    Variable(hr, 1)
    Act("Tick") {
        let increment: ActionExpr = (hr >= 1) && (hr <= 11) && (hr.next == hr + 1)
        let wrap: ActionExpr = (hr == 12) && (hr.next == 1)
        increment || wrap
    }
}
var clock = TLAStateMachine(hr: 1)
for _ in 1...4 { clock.apply(.tick); print("HourClock: \(clock.hr):00") }

// Shared specs verified by test suite
let demos: [TLASpec] = [DieHardSpec.spec, CoffeeCanSpec.spec]
for spec in demos {
    guard let graph = try? ModelChecker(spec: spec, maxStates: 10_000).exploreGraph() else { continue }
    print("\(spec.name): \(graph.states.count) states verified")
}
