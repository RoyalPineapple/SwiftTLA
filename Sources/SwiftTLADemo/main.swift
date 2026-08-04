import Foundation
import SwiftTLA
import SwiftTLAExamples

let registry = Dictionary(uniqueKeysWithValues: Examples.all.map { ($0.name.lowercased(), $0) })
let args = CommandLine.arguments.dropFirst()
let command = args.first ?? "interactive"
let name = args.dropFirst().first?.lowercased() ?? "hourclock"

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

func interactive(_ key: String) {
    guard let ex = registry[key] else { return print("Unknown: \(key)") }
    guard let graph = try? ModelChecker(spec: ex.spec, maxStates: 10_000).exploreGraph() else { return print("\(key): check failed") }
    guard let startID = graph.states.keys.min(by: { $0.id < $1.id }),
          let startState = graph.states[startID] else { return }
    
    var current = startState
    var currentID = startID
    
    while true {
        print("\nState: \(format(current))")
        let transitions = graph.transitions[currentID] ?? []
        if transitions.isEmpty { print("No moves."); break }
        print("Actions:")
        let indexed = Array(transitions.enumerated())
        for (i, t) in indexed { print("  \(i+1). \(t.action)") }
        print("  t. view TLA+    q. quit")
        print("> ", terminator: "")
        
        guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else { break }
        if input == "q" { break }
        if input == "t" { print("\n\(ex.spec.description)"); continue }
        guard let idx = Int(input), idx >= 1, idx <= transitions.count else { print("  ?"); continue }
        
        let chosen = transitions[idx - 1]
        current = graph.states[chosen.target]!
        currentID = chosen.target
        print("→ \(chosen.action)")
        print("State: \(format(current))")
    }
}

func format(_ state: [String: TLAValue]) -> String {
    state.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: " ")
}

switch command {
case "check": check(name)
case "tla": tla(name)
case "all": for ex in Examples.all { check(ex.name.lowercased()) }
case "interactive", "i": interactive(name)
default: print("demo check|tla|interactive|all [name]")
}
