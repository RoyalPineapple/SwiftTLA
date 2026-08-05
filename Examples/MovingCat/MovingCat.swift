import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct MovingCat {
    static var spec: TLASpec {
        TLASpec("MovingCat") {
            let cat = Var("cat", 3)
            let observed = Var("observed", 3)
            let direction = Var("direction", 1)
            Variable(cat, 3)
            Variable(observed, 3)
            Variable(direction, 1)

            Action("Move") {
                (direction == 1) && (cat < 6) && cat.becomes(cat + 1) && direction.stays && observed.stays ||
                (direction == 1) && (cat == 6) && cat.becomes(cat - 1) && direction.becomes(-1) && observed.stays ||
                (direction == -1) && (cat > 1) && cat.becomes(cat - 1) && direction.stays && observed.stays ||
                (direction == -1) && (cat == 1) && cat.becomes(cat + 1) && direction.becomes(1) && observed.stays ||
                (cat == observed) && observed.becomes(observed + 1) && cat.stays && direction.stays ||
                (cat == observed) && (observed == 6) && observed.becomes(1) && cat.stays && direction.stays
            }
        }
    }
}
