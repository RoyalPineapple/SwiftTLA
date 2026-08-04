import SwiftTLA
import SwiftTLAExamples

print("=== SwiftTLA — Layered Validation ===\n")

let examples: [(name: String, spec: TLASpec, expectedStates: Int)] = [
    ("HourClock", HourClockSpec.spec, 12),
    ("DieHard", DieHardSpec.spec, 16),
    ("CoffeeCan", CoffeeCanSpec.spec, 0),
]

// Layer 2: Verify state counts match TLC
print("--- Layer 2: State counts (cross-validated against TLC) ---")
for (name, spec, expected) in examples {
    guard let graph = try? ModelChecker(spec: spec, maxStates: 10_000).exploreGraph() else {
        print("\(name): FAILED"); continue
    }
    let ok = expected == 0 || graph.states.count == expected
    print("\(name): \(graph.states.count) states \(ok ? "✓" : "(expected \(expected))")")
}

// Layer 4: Dump canonical .tla
print("\n--- Layer 4: Canonical TLA+ (externally auditable) ---")
for (name, spec, _) in examples {
    let tla = spec.description
        .split(separator: "\n")
        .prefix(6)
        .joined(separator: "\n    ")
    print("\(name):\n    \(tla)\n")
}

print("Layer 1: swift test (algebraic matrix tests)")
print("Layer 3: make demo (hand-coded state machines)")
