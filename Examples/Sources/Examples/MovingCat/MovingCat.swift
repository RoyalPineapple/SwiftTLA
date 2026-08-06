import SwiftTLA

/// Moving cat — 6 boxes (upstream CatEvenBoxes). Not @TLAModel (parametric N).
public struct MovingCat {
    public static var spec: TLASpec { catSpec(boxes: 6) }

    static func catSpec(boxes: Int) -> TLASpec {
        let cat = Var<Int>("cat_box", value: 1)
        let observed = Var<Int>("observed_box", value: 2)
        let direction = Var<String>("direction", value: "right")
        return TLASpec("MovingCat") {
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
}
