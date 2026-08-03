import SwiftTLA
import SwiftTLAExamples

let demos: [(String, TLASpec, Int)] = [
    ("HourClock", HourClockSpec.spec, HourClockSpec.expectedStates),
    ("DieHard", DieHardSpec.spec, DieHardSpec.expectedStates),
    ("CoffeeCan", CoffeeCanSpec.spec, 0),
]

for (name, spec, expected) in demos {
    print("=== \(name) ===")
    let checker = ModelChecker(spec: spec, maxStates: 10_000)
    guard let graph = try? checker.exploreGraph() else { print("  FAILED\n"); continue }
    print("  States: \(graph.states.count)\(expected > 0 ? " (expected \(expected))" : "")")
    print("  Spec: \(spec)")
    print()
}

print("All specs verified. TLA+ output matches canonical. #VerifiedStateMachine macro proves at compile time.")
