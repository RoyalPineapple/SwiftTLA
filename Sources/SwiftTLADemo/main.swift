import Foundation
import SwiftTLA
import SwiftTLAExamples

let registry = Dictionary(uniqueKeysWithValues: Examples.all.map { ($0.name.lowercased(), $0) })
let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "all"
let name = args.dropFirst().first?.lowercased()

func check(_ key: String) {
    guard let ex = registry[key] else { return print("Unknown: \(key)") }
    guard let graph = try? ModelChecker(spec: ex.spec, maxStates: 10_000).exploreGraph() else { return print("\(key): FAILED") }
    let ok = ex.expectedStates == 0 || graph.states.count == ex.expectedStates
    print("\(key): \(graph.states.count) states \(ok ? "✓" : "(expected \(ex.expectedStates))")")
}

func tla(_ key: String) {
    guard let ex = registry[key] else { return print("Unknown: \(key)") }
    print(ex.spec.description)
}

switch command {
case "check": name.map(check) ?? print("Usage: demo check <\(registry.keys.sorted().joined(separator: "|"))>")
case "tla": name.map(tla) ?? print("Usage: demo tla <\(registry.keys.sorted().joined(separator: "|"))>")
case "all": for ex in Examples.all { check(ex.name.lowercased()) }
default: print("Commands: check <name>, tla <name>, all")
}
