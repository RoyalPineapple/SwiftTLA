import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct MovingCat {
    static var spec: TLASpec {
        TLASpec("MovingCat") {
            Extends("Naturals")
            let cat = Var("cat", value: 3)
            let observed = Var("observed", value: 3)
            let direction = Var("direction", value: 1)
            Variable(cat, 3)
            Variable(observed, 3)
            Variable(direction, 1)
            Definition("Number_Of_Boxes == 6")
            Invariant("TypeOK") { cat >= 1 && cat <= 6 && observed >= 2 && observed <= 5 && direction >= -1 && direction <= 1 }
            Action("Next") {
                (cat < 6 && cat.becomes(cat + 1) || cat > 1 && cat.becomes(cat - 1)) &&
                ((direction == 1 && observed < 5) && observed.becomes(observed + 1) && direction.stays ||
                 (direction == 1 && observed == 5) && observed.becomes(observed - 1) && direction.becomes(-1) ||
                 (direction == -1 && observed > 2) && observed.becomes(observed - 1) && direction.stays ||
                 (direction == -1 && observed == 2) && observed.becomes(observed + 1) && direction.becomes(1))
            }
        }
    }
}
