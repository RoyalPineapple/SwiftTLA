import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct MovingCat {
    static var spec: TLASpec {
        TLASpec("MovingCat") {
            let cat = Var(3)
            let observed = Var(3)
            let direction = Var(1)
            Action("move") {
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
