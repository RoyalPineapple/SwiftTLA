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

    let active = Var<TLAValue>("active")
    let pending = Var<TLAValue>("pending")
    let terminationDetected = Var<Bool>("terminationDetected")

    var activeInits = Set<TLAValue>()
    func genActive(_ i: Int, _ cur: [(Int, TLAValue)]) {
        if i >= N {
            activeInits.insert(.function(Dictionary(uniqueKeysWithValues: cur.map { (.int($0.0), $0.1) })))
        } else {
            genActive(i + 1, cur + [(i, .bool(true))])
            genActive(i + 1, cur + [(i, .bool(false))])
        }
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
                                                terminationDetected.stateExpr.isIn(boolSet)
            for i in 0..<N {
                let ci = StateExpr.value(.int(i))
                active.stateExpr.applying(ci).isIn(boolSet)
                pending.stateExpr.applying(ci) >= 0
            }
        }

        Invariant("Safe") {
                                                let terminated = StateExpr.forAll(nodeSet) { x in
                StateExpr.not(active.stateExpr.applying(x)) && StateExpr.equal(pending.stateExpr.applying(x), 0)
                                                }
            StateExpr.ifThenElse(terminationDetected.stateExpr, terminated, trueE)
        }

        Action("Terminate") {
            ActionExpr.exists("i", from: nodeSet) { i in
                                                                let terminated = StateExpr.forAll(nodeSet) { x in
                    StateExpr.not(active.stateExpr.applying(x)) && StateExpr.equal(pending.stateExpr.applying(x), 0)
                                                                }

                return active.stateExpr.applying(i)
                    && .assign(active.name, active.stateExpr.updated(at: i, to: falseE))
                    && pending.stays
                    && terminationDetected.becomes(
                        Expr(.ifThenElse(terminated, trueE, terminationDetected.stateExpr)))
            }
        }

        Action("RcvMsg") {
            ActionExpr.exists("i", from: nodeSet) { i in
                                                pending.stateExpr.applying(i) > 0
                    && .assign(active.name, active.stateExpr.updated(at: i, to: trueE))
                    && .assign(pending.name, pending.stateExpr.updated(at: i, to: pending.stateExpr.applying(i) - 1))
                    && terminationDetected.stays
            }
        }

        Action("SendMsg") {
            ActionExpr.exists("i", from: nodeSet) { i in
                ActionExpr.exists("j", from: nodeSet) { j in
                                                            active.stateExpr.applying(i)
                        && .assign(pending.name, pending.stateExpr.updated(at: j, to: pending.stateExpr.applying(j) + 1))
                        && active.stays
                        && terminationDetected.stays
                }
            }
        }

        Action("DetectTermination") {
                                    let terminated = StateExpr.forAll(nodeSet) { x in
                StateExpr.not(active.stateExpr.applying(x)) && StateExpr.equal(pending.stateExpr.applying(x), 0)
                                    }

            terminated
                && terminationDetected.becomes(Expr<Bool>(trueE))
                && active.stays
                && pending.stays
        }
    }
}
