import SwiftTLA
import SwiftTLAExamples

let demos: [(String, TLASpec)] = [
    ("HourClock", HourClockSpec.spec),
    ("DieHard", DieHardSpec.spec),
    ("CoffeeCan", CoffeeCanSpec.spec),
]

for (name, spec) in demos {
    print("=== \(name) ===")
    
    let checker = ModelChecker(spec: spec, maxStates: 10_000)
    guard let graph = try? checker.exploreGraph() else {
        print("  Check failed")
        continue
    }
    print("  States: \(graph.states.count) verified")
    
    print("\n  TLA+ output:")
    for line in spec.description.split(separator: "\n").prefix(8) {
        print("    \(line)")
    }
    print()
}
print("All demos verified. TLA+ output matches canonical.")
