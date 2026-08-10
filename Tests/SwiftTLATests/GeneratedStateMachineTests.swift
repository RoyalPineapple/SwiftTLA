import Testing
import SwiftTLA
import SwiftTLAMacros

// MARK: - Minimal spec: counter with no invariants

@TLAModel
struct CounterNoInvs {
    static var spec: TLASpec {
        TLASpec("CounterNoInvs") {
            let x = Var<Int>("x")
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 3) }
            Action("dec") { x.becomes(x - 1).when(x > 0) }
        }
    }
}

// MARK: - HourClock spec with invariants

@TLAModel
struct HourClock {
    static var spec: TLASpec {
        TLASpec("HourClock") {
            let hr = Var<Int>("hr")
            Variable(hr, 1)
            Action("Tick") { hr.becomes(hr + 1).when(hr < 12) }
            Action("Reset") { (hr == 12) && hr.becomes(1) }
            Invariant("TypeOK") { hr >= 1 && hr <= 12 }
        }
    }
}

// MARK: - Counter with explicit invariant

@TLAModel
struct CounterWithInv {
    static var spec: TLASpec {
        TLASpec("CounterWithInv") {
            let x = Var<Int>("x")
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 5) }
            Invariant("nonNeg") { x >= 0 }
        }
    }
}

// MARK: - Multi-variable spec with invariant

@TLAModel
struct MultiVar {
    static var spec: TLASpec {
        TLASpec("MultiVar") {
            let a = Var<Int>("a")
            let b = Var<Int>("b")
            Variable(a, 0)
            Variable(b, 0)
            Action("incA") { a.becomes(a + 1).when(a < 2) }
            Action("incB") { b.becomes(b + 1).when(b < 2) }
            Invariant("sumLE4") { (a + b) <= 4 }
        }
    }
}

// MARK: - Tests for generated verification methods

struct GeneratedStateMachineTests {
    @Test("verifySpec passes for CounterNoInvs")
    func counterNoInvsVerifySpec() throws {
        try CounterNoInvs.verifySpec()
    }

    @Test("verifyTransitions passes for CounterNoInvs")
    func counterNoInvsVerifyTransitions() throws {
        try CounterNoInvs.verifyTransitions()
    }

    @Test("transitionMatrix has correct entries for CounterNoInvs")
    func counterNoInvsTransitionMatrix() throws {
        let matrix = try CounterNoInvs.transitionMatrix()
        #expect(!matrix.isEmpty)
        for entry in matrix {
            #expect(entry.from.count >= 1)
            #expect(!entry.action.isEmpty)
            #expect(entry.to.count >= 1)
        }
    }

    @Test("verifySpec passes for HourClock")
    func hourClockVerifySpec() throws {
        try HourClock.verifySpec()
    }

    @Test("verifyTransitions passes for HourClock")
    func hourClockVerifyTransitions() throws {
        try HourClock.verifyTransitions()
    }

    @Test("verifyInvariants passes for HourClock")
    func hourClockVerifyInvariants() throws {
        try HourClock.verifyInvariants()
    }

    @Test("transitionMatrix has correct entries for HourClock")
    func hourClockTransitionMatrix() throws {
        let matrix = try HourClock.transitionMatrix()
        #expect(!matrix.isEmpty)
        for entry in matrix {
            #expect(entry.from.keys.contains("hr"))
            #expect(entry.to.keys.contains("hr"))
        }
    }

    @Test("verifySpec passes for CounterWithInv")
    func counterWithInvVerifySpec() throws {
        try CounterWithInv.verifySpec()
    }

    @Test("verifyInvariants passes for CounterWithInv")
    func counterWithInvVerifyInvariants() throws {
        try CounterWithInv.verifyInvariants()
    }

    @Test("verifySpec passes for MultiVar")
    func multiVarVerifySpec() throws {
        try MultiVar.verifySpec()
    }

    @Test("verifyInvariants passes for MultiVar")
    func multiVarVerifyInvariants() throws {
        try MultiVar.verifyInvariants()
    }

    @Test("transitionMatrix covers all reachable states for HourClock")
    func hourClockMatrixCoverage() throws {
        let matrix = try HourClock.transitionMatrix()
        let graph = try ModelChecker(spec: HourClock.spec, maxStates: 100_000).exploreGraph()
        #expect(!matrix.isEmpty)
        let fromStates = Set(matrix.map { $0.from })
        #expect(fromStates.count <= graph.states.count)
    }

    @Test("no self-contradictory transitions in CounterNoInvs")
    func counterNoInvsConsistency() throws {
        let matrix = try CounterNoInvs.transitionMatrix()
        for entry in matrix {
            let next = try CounterNoInvs.runtime.apply(actionName: entry.action, to: entry.from)
            #expect(next == entry.to)
        }
    }
}
