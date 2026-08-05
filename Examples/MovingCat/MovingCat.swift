import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct MovingCat {
    static var spec: TLASpec {
        TLASpec("MovingCat") {
            Extends("Naturals")
            let cat = Var<Int>("cat", value: 3)
            let observed = Var<Int>("observed", value: 3)
            let direction = Var<String>("direction", value: "right")
            Variable(cat, 3)
            Variable(observed, 3)
            Variable(direction, "right")
            Definition("Number_Of_Boxes == 6")
            Invariant("TypeOK") {
                cat >= 1 && cat <= 6 && observed >= 2 && observed <= 5 &&
                (direction == "left" || direction == "right")
            }
            Action("Next") {
                (cat < 6 && cat.becomes(cat + 1) || cat > 1 && cat.becomes(cat - 1)) &&
                ((direction == "right" && observed < 5) && observed.becomes(observed + 1) ||
                 (direction == "right" && observed == 5) && observed.becomes(observed - 1) && direction.becomes("left") ||
                 (direction == "left" && observed > 2) && observed.becomes(observed - 1) ||
                 (direction == "left" && observed == 2) && observed.becomes(observed + 1) && direction.becomes("right"))
            }
        }
    }
}
