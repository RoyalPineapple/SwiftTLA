import SwiftTLA

// Dining Philosophers — Chandy-Misra solution. NP=5.
// Port: 1:1 structural match. TypeOK + ExclusiveAccess. 67 states.
// Upstream: specifications/DiningPhilosophers/DiningPhilosophers.tla

extension Example {
    static let diningPhilosophersNP5 = Example.Entry(
        id: "DiningPhilosophers/DiningPhilosophers",
        upstreamSpec: "DiningPhilosophers",
        upstreamModule: "specifications/DiningPhilosophers/DiningPhilosophers.tla",
        upstreamCfg: "specifications/DiningPhilosophers/DiningPhilosophers.cfg",
        expectedDistinct: 67,
        expectedResult: "success",
        spec: diningPhilosophersSpec(),
        notes: "NP=5. Records (holder/clean), existsAction, ExclusiveAccess. Matching upstream structure.",
        matchesUpstreamTLC: true
    )
}

private func diningPhilosophersSpec() -> TLASpec {
    let NP = 5

    let forks = Var<TLAFunctionType>("forks")
    let pc = Var<TLAFunctionType>("pc")
    let hungry = Var<TLAFunctionType>("hungry")

    let loop = StateExpr.value(.string("Loop"))
    let eat = StateExpr.value(.string("Eat"))
    let think = StateExpr.value(.string("Think"))
    let trueE = StateExpr.value(.bool(true))
    let falseE = StateExpr.value(.bool(false))
    let npE = StateExpr.value(.int(NP))

    func rec(_ f: StateExpr, _ field: String) -> StateExpr { .recordAccess(f, field) }
    func leftFork(_ p: StateExpr) -> StateExpr { p }
    func rightFork(_ p: StateExpr) -> StateExpr {
        StateExpr.ifThenElse(StateExpr.equal(p, npE), 1, p + 1)
    }
    func leftPhilosopher(_ p: StateExpr) -> StateExpr {
        StateExpr.ifThenElse(StateExpr.equal(p, 1), npE, p - 1)
    }
    func rightPhilosopher(_ p: StateExpr) -> StateExpr {
        StateExpr.ifThenElse(StateExpr.equal(p, npE), 1, p + 1)
    }

    var forkInits: [TLAValue: TLAValue] = [:]
    for fk in 1...NP {
        forkInits[.int(fk)] = .record(["holder": .int(fk == 2 ? 1 : fk), "clean": .bool(false)])
    }
    let hungryInit = TLAValue.function(Dictionary(uniqueKeysWithValues: (1...NP).map { (.int($0), .bool(true)) }))
    let pcInit = TLAValue.function(Dictionary(uniqueKeysWithValues: (1...NP).map { (.int($0), .string("Loop")) }))

    func typeOkLine(_ i: Int) -> StateExpr {
        let ci = StateExpr.value(.int(i))
        let f = StateExpr.variable("forks")
        let h = StateExpr.variable("hungry")
        let p = StateExpr.variable("pc")
        return rec(f.applying(ci), "holder") >= 1
            && rec(f.applying(ci), "holder") <= NP
            && rec(f.applying(ci), "clean").isIn(StateExpr.set([trueE, falseE]))
            && h.applying(ci).isIn(StateExpr.set([trueE, falseE]))
            && p.applying(ci).isIn(StateExpr.set([loop, eat, think]))
    }

    func exclusiveLine(_ i: Int, _ j: Int) -> StateExpr {
        let p = StateExpr.variable("pc")
        let pi = StateExpr.value(.int(i))
        let pj = StateExpr.value(.int(j))
        let sharesFork = StateExpr.intersection(
            StateExpr.set([leftFork(pi), rightFork(pi)]),
            StateExpr.set([leftFork(pj), rightFork(pj)]))
        return StateExpr.not(
            sharesFork.cardinality > 0
            && StateExpr.equal(p.applying(pi), eat)
            && StateExpr.equal(p.applying(pj), eat))
    }

    return TLASpec("DiningPhilosophers") {
        Extends("Integers")

        Variable(forks, TLAValue.function(forkInits))
        Variable(pc, pcInit)
        Variable(hungry, hungryInit)

        Invariant("TypeOK") {
            for i in 1...NP { typeOkLine(i) }
        }

        Invariant("ExclusiveAccess") {
            for i in 1...NP {
                for j in 1...NP where i != j { exclusiveLine(i, j) }
            }
        }

        for p in 1...NP {
            let pE = StateExpr.value(.int(p))
            let lf = leftFork(pE)
            let rf = rightFork(pE)
            let lp = leftPhilosopher(pE)
            let rp = rightPhilosopher(pE)

            let hld = rec(StateExpr.variable("forks").applying(lf), "holder")
            let lc = rec(StateExpr.variable("forks").applying(lf), "clean")
            let hrd = rec(StateExpr.variable("forks").applying(rf), "holder")
            let rc = rec(StateExpr.variable("forks").applying(rf), "clean")

            let canEat = StateExpr.equal(hld, pE) && StateExpr.equal(hrd, pE)
                && StateExpr.equal(lc, trueE) && StateExpr.equal(rc, trueE)

            // Loop: pass dirty forks to neighbor, then update pc
            let passLeft: ActionExpr = .and(.guard_(StateExpr.equal(hld, pE) && StateExpr.equal(lc, falseE)),
                .assign("forks", StateExpr.variable("forks").updated(at: lf, to: StateExpr.recordLiteral(["holder": lp, "clean": trueE]))))
            let passRight: ActionExpr = .and(.guard_(
                StateExpr.equal(hrd, pE) && StateExpr.equal(rc, falseE)
                    && StateExpr.not(StateExpr.equal(hld, pE) && StateExpr.equal(lc, falseE))),
                .assign("forks", StateExpr.variable("forks").updated(at: rf, to: StateExpr.recordLiteral(["holder": rp, "clean": trueE]))))
            let keepGuards: StateExpr = StateExpr.not(StateExpr.equal(hld, pE) && StateExpr.equal(lc, falseE))
                && StateExpr.not(StateExpr.equal(hrd, pE) && StateExpr.equal(rc, falseE))

            let hSe = StateExpr.variable("hungry")
            let goEat: ActionExpr = .and(.guard_(canEat && StateExpr.equal(hSe.applying(pE), trueE)),
                .assign("pc", StateExpr.variable("pc").updated(at: pE, to: eat)))
            let stayLoopPc: ActionExpr = .and(.guard_(StateExpr.not(canEat) && StateExpr.equal(hSe.applying(pE), trueE)),
                .assign("pc", StateExpr.variable("pc").updated(at: pE, to: loop)))
            let goThinkPc: ActionExpr = .and(.guard_(StateExpr.not(StateExpr.equal(hSe.applying(pE), trueE))),
                .assign("pc", StateExpr.variable("pc").updated(at: pE, to: think)))

            let forkBranch: ActionExpr = .or(passLeft, .or(passRight, .guard_(keepGuards)))
            let pcBranch: ActionExpr = .or(goEat, .or(stayLoopPc, goThinkPc))

            Action("Loop_\(p)") {
                StateExpr.variable("pc").applying(pE) == loop
                && forkBranch
                && pcBranch
            }
            Action("Think_\(p)") {
                StateExpr.variable("pc").applying(pE) == think
                && hungry.becomes(hSe.updated(at: pE, to: trueE))
                && pc.becomes(StateExpr.variable("pc").updated(at: pE, to: loop))
            }
            Action("Eat_\(p)") {
                StateExpr.variable("pc").applying(pE) == eat
                && hungry.becomes(hSe.updated(at: pE, to: falseE))
                && pc.becomes(StateExpr.variable("pc").updated(at: pE, to: loop))
                && forks.becomes(StateExpr.variable("forks")
                    .updated(at: lf, to: StateExpr.recordLiteral(["holder": hld, "clean": falseE]))
                    .updated(at: rf, to: StateExpr.recordLiteral(["holder": hrd, "clean": falseE])))
            }
        }
    }
}
