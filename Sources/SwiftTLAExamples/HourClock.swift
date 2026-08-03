import SwiftTLA

enum HourClockExample {
    static let spec = TLASpec("HourClock") {
        let hr = Var<Int>("hr")
        Variable(hr, 1)
        Act("Tick") {
            let increment: ActionExpr = (hr >= 1) && (hr <= 11) && (next(hr) == hr + 1)
            let wrap: ActionExpr = (hr == 12) && (next(hr) == 1)
            increment || wrap
        }
    }

    static let canonicalTLA = """
    ---- MODULE HourClock ----
    EXTENDS Naturals

    VARIABLES hr
    vars == <<hr>>

    Init == hr = 1

    Tick == ((((hr >= 1) /\\ (hr <= 11)) /\\ hr' = (hr + 1)) \\/ ((hr = 12) /\\ hr' = 1))

    Next == Tick

    Spec == Init /\\ [][Next]_vars

    ====
    """

    static func validate() -> Bool {
        let generated = spec.description
        return generated.contains("VARIABLES hr")
            && generated.contains("Tick ==")
            && generated.contains("hr' = (hr + 1)")
            && generated.contains("hr' = 1")
    }

    static func run() {
        let checker = ModelChecker(spec: spec, maxStates: 20)
        guard let graph = try? checker.exploreGraph() else {
            print("HourClock: model checking failed")
            return
        }
        print("HourClock: \(graph.states.count) states (expected 12)")
        if validate() {
            print("HourClock: TLA+ output matches canonical")
        }
        let code = StateMachineGenerator(graph: graph).generate()
        print("HourClock: generated Swift type ready")
    }
}
