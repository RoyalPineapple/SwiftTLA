import SwiftTLA
import SwiftTLAMacros

    // MARK: Helpers

func recordMessage(_ fields: [String: String]) -> TLAValue {
        .record(.init(fields.map { .init($0.key, .string($0.value)) }))
    }

func recordMessageExpr(_ fields: [String: StateExpr]) -> StateExpr {
        StateExpr.record(fields)
    }

func coffeeCans(maxBeanCount: Int) -> [TLAValue] {
        var cans: [TLAValue] = []
        for black in 0...maxBeanCount {
            for white in 0...maxBeanCount where (1...maxBeanCount).contains(black + white) {
                cans.append(.record(["black": .int(black), "white": .int(white)]))
            }
        }
        return cans
    }

func coffeeCanSpec(maxBeanCount: Int) -> TLASpec {
        let can = Var<TLAValue>("can")
        let cans = coffeeCans(maxBeanCount: maxBeanCount)
        return #spec("CoffeeCan") {
            Extends(.naturals)
            Variable(can, in: cans)
            Action("PickSameColorBlack") {
                StateExpr.recordAccess(can.stateExpr, "black")
                    + StateExpr.recordAccess(can.stateExpr, "white") > 1
                    && StateExpr.recordAccess(can.stateExpr, "black") >= 2
                    && .assign(.named(can.name), can.stateExpr.updated(at: "black", to: StateExpr.recordAccess(can.stateExpr, "black") - 1))
            }
            Action("PickSameColorWhite") {
                StateExpr.recordAccess(can.stateExpr, "black")
                    + StateExpr.recordAccess(can.stateExpr, "white") > 1
                    && StateExpr.recordAccess(can.stateExpr, "white") >= 2
                    && .assign(.named(can.name),
                        StateExpr.except(
                            StateExpr.except(
                                .variable("can"),
                                .value(.string("black")),
                                StateExpr.recordAccess(can.stateExpr, "black") + 1
                            ),
                            .value(.string("white")),
                            StateExpr.recordAccess(can.stateExpr, "white") - 2
                        )
                    )
            }
            Action("PickDifferentColor") {
                StateExpr.recordAccess(can.stateExpr, "black")
                    + StateExpr.recordAccess(can.stateExpr, "white") > 1
                    && StateExpr.recordAccess(can.stateExpr, "black") >= 1
                    && StateExpr.recordAccess(can.stateExpr, "white") >= 1
                    && .assign(.named(can.name), can.stateExpr.updated(at: "black", to: StateExpr.recordAccess(can.stateExpr, "black") - 1))
            }
            Action("Termination") {
                StateExpr.recordAccess(can.stateExpr, "black") + StateExpr.recordAccess(can.stateExpr, "white") == 1
            }
            Invariant("TypeInvariant") {
                StateExpr.recordAccess(can.stateExpr, "black") >= 0 && StateExpr.recordAccess(can.stateExpr, "black") <= maxBeanCount
                    && StateExpr.recordAccess(can.stateExpr, "white") >= 0 && StateExpr.recordAccess(can.stateExpr, "white") <= maxBeanCount
            }
        }
    }
