import Foundation
import SwiftTLA
import SwiftTLAExamples

let specs: [String: (spec: TLASpec, expected: Int)] = [
    "hourclock": (HourClockSpec.spec, 12),
    "diehard": (DieHardSpec.spec, 16),
    "coffeecan": (CoffeeCanSpec.spec, 0),
]

let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "all"
let name = args.dropFirst().first

func check(_ key: String) {
    guard let (spec, expected) = specs[key] else { return print("Unknown: \(key)") }
    guard let graph = try? ModelChecker(spec: spec, maxStates: 10_000).exploreGraph() else { return print("\(key): FAILED") }
    let ok = expected == 0 || graph.states.count == expected
    print("\(key): \(graph.states.count) states \(ok ? "✓" : "(expected \(expected))")")
}

func tla(_ key: String) {
    guard let (spec, _) = specs[key] else { return print("Unknown: \(key)") }
    print(spec.description)
}

func help() {
    print("Commands: check <name>, tla <name>, all")
    print("Names: \(specs.keys.sorted().joined(separator: ", "))")
}

switch command {
case "check": name.map(check) ?? help()
case "tla": name.map(tla) ?? help()
case "all":
    for key in specs.keys { check(key) }
case "layer3":
    print("Run: make demo")
default: help()
}
