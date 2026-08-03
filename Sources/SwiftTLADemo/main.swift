import SwiftTLA
import SwiftTLAExamples
import SwiftTLAMacros

let hr = Var<Int>("hr")

// Compile-time: #TLASpec generates a verified struct, checked during compilation
#TLASpec {
    Variable(hr, 1)
    Act("Tick") {
        let increment: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
        let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
        increment || wrap
    }
}

var clock = TLA(hr: 1)
print("=== HourClock (compile-time verified) ===")
for _ in 1...3 { clock.apply(.tick); print("  \(clock.hr):00") }
print()

// Runtime: shared specs checked by test suite
let demos: [TLASpec] = [
    DieHardSpec.spec,
    CoffeeCanSpec.spec,
]

for spec in demos {
    guard let graph = try? ModelChecker(spec: spec, maxStates: 10_000).exploreGraph() else {
        print("=== \(spec.name) === FAILED"); continue
    }
    print("=== \(spec.name) === \(graph.states.count) states verified")
}
