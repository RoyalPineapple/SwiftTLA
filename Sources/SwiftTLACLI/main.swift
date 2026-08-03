import ArgumentParser
import SwiftTLA
import SwiftTLAGenerator

@main
struct SwiftTLACLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-tla",
        abstract: "A Swifty TLA+ model checker",
        subcommands: [Check.self, Generate.self, Tla.self, ListExamples.self]
    )
}

struct Check: ParsableCommand {
    @Argument(help: "The example to run (counter, diehard)")
    var example: String

    func run() throws {
        let spec = try resolveSpec(example)
        print("Checking \(spec.name)...")
        let checker = ModelChecker(spec: spec)
        let result = try checker.check()
        print(result)
    }
}

struct Generate: ParsableCommand {
    @Argument(help: "The example to generate from (diehard)")
    var example: String

    func run() throws {
        let spec = try resolveSpec(example)
        let checker = ModelChecker(spec: spec, maxStates: 10_000)
        let graph = try checker.exploreGraph()
        let generator = StateMachineGenerator(graph: graph)
        print(generator.generate())
    }
}

struct Tla: ParsableCommand {
    @Argument(help: "The example to emit TLA+ for (diehard, counter, hourclock)")
    var example: String

    func run() throws {
        let spec = try resolveSpec(example)
        let name = spec.name.replacingOccurrences(of: " ", with: "")
        let vars = spec.variables.map(\.name)
        let varDecl = vars.joined(separator: ", ")

        print("---- MODULE \(name) ----")
        print("EXTENDS Naturals, FiniteSets, Sequences")
        print()
        print("VARIABLES \(varDecl)")
        print("vars == <<\(vars.joined(separator: ", "))>>")
        print()

        let initExpr = vars.map { v in
            "\(v) = \(spec.variables.first(where: { $0.name == v })!.initial)"
        }.joined(separator: " /\\ ")
        print("Init == \(initExpr)")
        print()

        for act in spec.actions where !act.name.isEmpty {
            print("\(act.name) == \(act.body)")
            print()
        }

        let next = spec.actions.filter { !$0.name.isEmpty }.map(\.name).joined(separator: " \\/ ")
        print("Next == \(next)")
        print()
        print("Spec == Init /\\ [][Next]_vars")

        for inv in spec.invariants where !inv.name.isEmpty {
            print()
            print("\(inv.name) == \(inv.body)")
        }

        print()
        print("====")
    }
}

struct ListExamples: ParsableCommand {
    func run() {
        print("Available examples:")
        print("  counter  — Increment/decrement with invariant x >= 0")
        print("  diehard  — Die Hard water jug puzzle")
    }
}

func resolveSpec(_ name: String) throws -> TLASpec {
    switch name.lowercased() {
    case "counter": return counterSpec
    case "diehard": return dieHardGraphSpec
    case "hourclock": return hourClockSpec
    default: throw ValidationError("Unknown example '\(name)'. Available: counter, diehard, hourclock")
    }
}

let counterSpec: TLASpec = {
    let x = Var<Int>("x")
    return TLASpec("Counter") {
        Variable(x, 0)
        Act("Inc") { next(x) == x + 1 }
        Act("Dec") { next(x) == x - 1 }
        Inv("NonNeg") { x >= 0 }
    }
}()

let dieHardPuzzleSpec: TLASpec = {
    let jug3 = Var<Int>("jug3")
    let jug5 = Var<Int>("jug5")
    return TLASpec("DieHard") {
        Variable(jug3, 0)
        Variable(jug5, 0)
        Act("Fill3") { next(jug3) == 3 }
        Act("Fill5") { next(jug5) == 5 }
        Act("Empty3") { next(jug3) == 0 }
        Act("Empty5") { next(jug5) == 0 }
        Act("Pour3to5") {
            let pour: ActionExpr = (jug3 + jug5 <= 5) && (next(jug5) == jug3 + jug5) && (next(jug3) == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 5)) && (next(jug5) == 5) && (next(jug3) == jug3 - (5 - jug5))
            pour || spill
        }
        Act("Pour5to3") {
            let pour: ActionExpr = (jug3 + jug5 <= 3) && (next(jug3) == jug3 + jug5) && (next(jug5) == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 3)) && (next(jug3) == 3) && (next(jug5) == jug5 - (3 - jug3))
            pour || spill
        }
        Inv("jug5_ne_4") { jug5 != 4 }
    }
}()

let dieHardGraphSpec: TLASpec = {
    let jug3 = Var<Int>("jug3")
    let jug5 = Var<Int>("jug5")
    return TLASpec("DieHard") {
        Variable(jug3, 0)
        Variable(jug5, 0)
        Act("Fill3") { next(jug3) == 3 }
        Act("Fill5") { next(jug5) == 5 }
        Act("Empty3") { next(jug3) == 0 }
        Act("Empty5") { next(jug5) == 0 }
        Act("Pour3to5") {
            let pour: ActionExpr = (jug3 + jug5 <= 5) && (next(jug5) == jug3 + jug5) && (next(jug3) == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 5)) && (next(jug5) == 5) && (next(jug3) == jug3 - (5 - jug5))
            pour || spill
        }
        Act("Pour5to3") {
            let pour: ActionExpr = (jug3 + jug5 <= 3) && (next(jug3) == jug3 + jug5) && (next(jug5) == 0)
            let spill: ActionExpr = (!(jug3 + jug5 <= 3)) && (next(jug3) == 3) && (next(jug5) == jug5 - (3 - jug3))
            pour || spill
        }
    }
}()

let hourClockSpec: TLASpec = {
    let hr = Var<Int>("hr")
    return TLASpec("HourClock") {
        Variable(hr, 1)
        Act("Tick") {
            let inc: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
            let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
            inc || wrap
        }
        Inv("ValidHour") { (hr >= 1) && (hr <= 12) }
    }
}()
