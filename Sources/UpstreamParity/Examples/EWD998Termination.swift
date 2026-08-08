import SwiftTLA

// Ring termination detection (EWD998). N=4. StateConstraint bounds pending.
// TypeOK + Safe. 17 states.
// Upstream: specifications/ewd998/AsyncTerminationDetection.tla

extension Example {
    static let ewd998 = Example.Entry(
        id: "ewd998/AsyncTerminationDetection",
        upstreamSpec: "ewd998",
        upstreamModule: "specifications/ewd998/AsyncTerminationDetection.tla",
        upstreamCfg: "specifications/ewd998/AsyncTerminationDetection.cfg",
        expectedDistinct: 4097,
        spec: ewd998Spec(),
        notes: "N=4. Nondet init for active. Constraint pending<=3. Safe.",
    )
}

private func ewd998Spec() -> TLASpec {
    let N = 4
    let nodeSet = StateExpr.setLiteral((0..<N).map { StateExpr.value(.int($0)) })
    let trueE = StateExpr.value(.bool(true))
    let falseE = StateExpr.value(.bool(false))
    let boolSet = StateExpr.set([trueE, falseE])

    let active = Var<TLAFunctionType>("active")
    let pending = Var<TLAFunctionType>("pending")
    let terminationDetected = Var<Bool>("terminationDetected")

    var activeInits = Set<TLAValue>()
    func genActive(_ i: Int, _ cur: [(Int, TLAValue)]) {
        if i >= N { activeInits.insert(.function(Dictionary(uniqueKeysWithValues: cur.map { (.int($0.0), $0.1) }))) } else { genActive(i+1, cur+[(i, .bool(true))]); genActive(i+1, cur+[(i, .bool(false))]) }
    }
    genActive(0, [])

    let stateC = StateExpr.forAll(nodeSet) { x in
        StateExpr.variable("pending").applying(x) <= 3
    }

    return TLASpec("AsyncTerminationDetection") {
        Extends("Naturals")

        Variable(active, in: activeInits)
        Variable(pending, TLAValue.function(Dictionary(uniqueKeysWithValues: (0..<N).map { (.int($0), .int(0)) })))
        Variable(terminationDetected, false)
        Constraint(stateC)

        Invariant("TypeOK") {
            let a = StateExpr.variable("active")
            let p = StateExpr.variable("pending")
            let t = StateExpr.variable("terminationDetected")
            t.isIn(boolSet)
            for i in 0..<N {
                let ci = StateExpr.value(.int(i))
                a.applying(ci).isIn(boolSet)
                p.applying(ci) >= 0
            }
        }

        Invariant("Safe") {
            let t = StateExpr.variable("terminationDetected")
            let a = StateExpr.variable("active")
            let p = StateExpr.variable("pending")
            let terminated = StateExpr.forAll(nodeSet) { x in
                StateExpr.not(a.applying(x)) && StateExpr.equal(p.applying(x), 0)
            }
            StateExpr.ifThenElse(t, terminated, trueE)
        }

        Action("Terminate") {
            ActionExpr.exists("i", from: nodeSet) { i in
                let a = StateExpr.variable("active")
                let p = StateExpr.variable("pending")
                let t = StateExpr.variable("terminationDetected")
                let terminated = StateExpr.forAll(nodeSet) { x in
                    StateExpr.not(a.applying(x)) && StateExpr.equal(p.applying(x), 0)
                }

                return a.applying(i)
                    && active.becomes(Expr(.except(a, i, falseE)))
                    && pending.stays
                    && terminationDetected.becomes(
                        StateExpr.ifThenElse(terminated, trueE, t))
            }
        }

        Action("RcvMsg") {
            ActionExpr.exists("i", from: nodeSet) { i in
                let a = StateExpr.variable("active")
                let p = StateExpr.variable("pending")
                return p.applying(i) > 0
                    && active.becomes(Expr(.except(a, i, trueE)))
                    && pending.becomes(p.updated(at: i, to: p.applying(i) - 1))
                    && terminationDetected.stays
            }
        }

        Action("SendMsg") {
            ActionExpr.exists("i", from: nodeSet) { i in
                ActionExpr.exists("j", from: nodeSet) { j in
                    let a = StateExpr.variable("active")
                    let p = StateExpr.variable("pending")
                    return a.applying(i)
                        && pending.becomes(p.updated(at: j, to: p.applying(j) + 1))
                        && active.stays
                        && terminationDetected.stays
                }
            }
        }

        Action("DetectTermination") {
            let a = StateExpr.variable("active")
            let p = StateExpr.variable("pending")
            let terminated = StateExpr.forAll(nodeSet) { x in
                StateExpr.not(a.applying(x)) && StateExpr.equal(p.applying(x), 0)
            }

            terminated
                && terminationDetected.becomes(trueE)
                && active.stays
                && pending.stays
        }
    }
}
