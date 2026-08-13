import SwiftTLA
import SwiftTLAMacros

// Single-lane bridge. 2R+2L cars, bridge {4,5}. 170 states.
// Port: 1:1 structural match. Safety invariants. 170 states.
// Upstream: specifications/SingleLaneBridge/SingleLaneBridge.tla

@TLAModel
public struct SingleLaneBridgeModel {
    public static var spec: TLASpec {
        let carsRight: Set<TLAValue> = [.string("r1"), .string("r2")]
        let carsLeft: Set<TLAValue>  = [.string("l1"), .string("l2")]
        let allCars = carsRight.union(carsLeft).sorted()
        let bridge: Set<Int> = [4, 5]
        let startPos = 1; let endPos = 8; let startBridge = 4; let endBridge = 5

        let carsSet = StateExpr.setLiteral(allCars.map { .value($0) })
        let bridgeSet = StateExpr.setLiteral(bridge.map { .value(.int($0)) })
        let rightSet = StateExpr.setLiteral(carsRight.map { .value($0) })
        let sp = StateExpr.value(.int(startPos))
        let ep = StateExpr.value(.int(endPos))
        let sb = StateExpr.value(.int(startBridge))
        let eb = StateExpr.value(.int(endBridge))

        func isRight(_ c: StateExpr) -> StateExpr { c.isIn(rightSet) }
        func inBridge(_ p: StateExpr) -> StateExpr { p.isIn(bridgeSet) }
        func rMove(_ p: StateExpr) -> StateExpr { .ifThenElse(p > sp, p - 1, ep) }
        func lMove(_ p: StateExpr) -> StateExpr { .ifThenElse(p < ep, p + 1, sp) }

        var locInit: [TLAValue: TLAValue] = [:]
        for car in allCars { locInit[car] = .int(carsRight.contains(car) ? endPos : startPos) }

        return TLASpec("SingleLaneBridge") {
            Extends("Naturals")
            Constant("CarsRight", TLAValue.set(carsRight))
            Constant("CarsLeft", TLAValue.set(carsLeft))
            Constant("Bridge", TLAValue.set(Set(bridge.map { TLAValue.int($0) })))
            Constant("Positions", TLAValue.set(Set((1...8).map { TLAValue.int($0) })))

            let lv = Var<TLAValue>("Location")
            let wv = Var<TLAValue>("WaitingBeforeBridge")

            DefineRecursive("SeqFromSet", params: ["S"]) {
                let s = StateExpr.variable("S")
                let chosen = StateExpr.choose(from: s, matching: StateExpr.value(.bool(true)))
                StateExpr.ifThenElse(
                    StateExpr.equal(StateExpr.setLiteral([]), s),
                    StateExpr.tupleLiteral([]),
                    StateExpr.tupleConcatenate(
                        StateExpr.tupleLiteral([chosen]),
                        StateExpr.recursiveCall("SeqFromSet", [
                            StateExpr.setDifference(s, StateExpr.setLiteral([chosen]))
                        ])
                    )
                )
            }

            Variable(lv, TLAValue.function(locInit))
            Variable(wv, TLAValue.tuple([]))

            Invariant("Invariants") {
                let l = StateExpr.variable("Location")
                let carsInBridge = StateExpr.filterSet(carsSet) { x in inBridge(l.applying(x)) }

                for a in allCars {
                    let ia = StateExpr.value(a)
                    for b in allCars where a < b {
                        let ib = StateExpr.value(b)
                        StateExpr.not(inBridge(l.applying(ia))
                            && StateExpr.equal(l.applying(ia), l.applying(ib)))
                    }
                }
                carsInBridge.cardinality < bridge.count + 1
                for r in carsRight {
                    let ir = StateExpr.value(r)
                    for lc in carsLeft {
                        let il = StateExpr.value(lc)
                        StateExpr.not(inBridge(l.applying(ir)) && inBridge(l.applying(il)))
                    }
                }
            }

            for car in allCars {
                let c = StateExpr.value(car)
                let carName: String = { if case .string(let s) = car { return s }; return "\(car)" }()
                let l = StateExpr.variable("Location")
                let w = StateExpr.variable("WaitingBeforeBridge")
                let nl: StateExpr = .ifThenElse(isRight(c), rMove(l.applying(c)), lMove(l.applying(c)))
                let inBrSet = StateExpr.filterSet(carsSet) { x in inBridge(l.applying(x)) }
                let isInBridge = c.isIn(inBrSet)
                let leavingBridge = (isRight(c) && nl == eb + 1) || (!isRight(c) && nl == sb - 1)

                let changeLocWithQ: ActionExpr = .and(.guard_(leavingBridge),
                    .and(.assign("Location", l.updated(at: c, to: nl)),
                        .assign("WaitingBeforeBridge", w.appending(c))))
                let changeLocNoQ: ActionExpr = .and(.guard_(StateExpr.not(leavingBridge)),
                    .and(.assign("Location", l.updated(at: c, to: nl)),
                        .unchanged("WaitingBeforeBridge")))
                let changeLoc: ActionExpr = .or(changeLocWithQ, changeLocNoQ)

                Action("MoveOutside_\(carName)") {
                    .and(.guard_(StateExpr.not(inBridge(nl)) && StateExpr.notEqual(nl, l.applying(c))),
                    changeLoc)
                }

                Action("MoveInside_\(carName)") {
                    .and(.guard_(isInBridge
                        &&                     StateExpr.forAll(carsSet) { x in StateExpr.notEqual(l.applying(x), nl) }),
                    changeLoc)
                }

                let h = w.head
                let sameDir = StateExpr.forAll(inBrSet) { x in
                    StateExpr.equal(isRight(x), isRight(c))
                }
                let noCollision = StateExpr.forAll(carsSet) { x in
                    StateExpr.notEqual(l.applying(x), nl)
                }

                let enterBridge1: ActionExpr = .and(.guard_(
                    inBrSet.cardinality == 0 && w.count > 0 && h == c),
                    .and(.assign("Location", l.updated(at: c, to: nl)),
                        .assign("WaitingBeforeBridge", w.tail)))
                let enterBridge2: ActionExpr = .and(.guard_(
                    w.count > 0 && h == c && !h.isIn(inBrSet) && sameDir && noCollision),
                    .and(.assign("Location", l.updated(at: c, to: nl)),
                        .assign("WaitingBeforeBridge", w.tail)))
                let enterBridge: ActionExpr = .or(enterBridge1, enterBridge2)

                Action("Enter_\(carName)") {
                    .and(.guard_(w.count > 0 && h == c), enterBridge)
                }
            }
        }
    }
}

extension Example {
    static let singleLaneBridge = Example.Entry(
        id: "SingleLaneBridge/MC",
        upstreamSpec: "SingleLaneBridge",
        upstreamModule: "specifications/SingleLaneBridge/SingleLaneBridge.tla",
        upstreamCfg: "specifications/SingleLaneBridge/MC.cfg",
        expectedDistinct: 3605,
        spec: SingleLaneBridgeModel.spec,
        notes: "2R+2L, bridge {4,5}. forAll/filterSet builders, ifElse. 3605 states.",
    )
}
