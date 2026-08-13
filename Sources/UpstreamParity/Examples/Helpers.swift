import SwiftTLA

    // MARK: Helpers

func recordMessage(_ fields: [String: String]) -> TLAValue {
        .record(fields.mapValues { .string($0) })
    }

func recordMessageExpr(_ fields: [String: StateExpr]) -> StateExpr {
        .recordLiteral(fields)
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
        return TLASpec("CoffeeCan") {
            Extends("Naturals")
            Variable(can, in: cans)
            Action("PickSameColorBlack") {
                StateExpr.recordAccess(can.stateExpr, "black")
                    + StateExpr.recordAccess(can.stateExpr, "white") > 1
                    && StateExpr.recordAccess(can.stateExpr, "black") >= 2
                    && .assign(can.name, can.stateExpr.updated(at: "black", to: StateExpr.recordAccess(can.stateExpr, "black") - 1))
            }
            Action("PickSameColorWhite") {
                StateExpr.recordAccess(can.stateExpr, "black")
                    + StateExpr.recordAccess(can.stateExpr, "white") > 1
                    && StateExpr.recordAccess(can.stateExpr, "white") >= 2
                    && .assign(can.name,
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
                    && .assign(can.name, can.stateExpr.updated(at: "black", to: StateExpr.recordAccess(can.stateExpr, "black") - 1))
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

    /// Faithful Moving_Cat_Puzzle algorithm for fixed Number_Of_Boxes.
func catSpec(boxes: Int) -> TLASpec {
        let cat = Var<Int>("cat_box")
        let observed = Var<Int>("observed_box")
        let direction = Var<String>("direction")
        return TLASpec("Cat") {
            Extends("Naturals")
            Variable(cat, in: 1...boxes)
            Variable(observed, in: 2...(boxes - 1))
            Variable(direction, in: ["left", "right"])
            Invariant("TypeOK") {
                cat >= 1 && cat <= boxes
                    && observed >= 2 && observed <= boxes - 1
                    && (direction == "left" || direction == "right")
            }
            Action("Next") {
                // Move_Cat /\ Observe_Box
                ((cat < boxes && cat.becomes(cat + 1)) || (cat > 1 && cat.becomes(cat - 1)))
                    && (
                        (direction == "right" && observed < boxes - 1 && observed.becomes(observed + 1))
                            || (direction == "right" && observed == boxes - 1 && direction.becomes("left"))
                            || (direction == "left" && observed > 2 && observed.becomes(observed - 1))
                            || (direction == "left" && observed == 2 && direction.becomes("right"))
                    )
            }
        }
    }
