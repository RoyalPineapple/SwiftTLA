import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct MovingCat {
    var cat = Var(3)
    var observed = Var(3)
    var direction = Var(1)
    let N = 6

    func move() {
        (direction == 1) && (cat < N) && cat.becomes(cat + 1) && direction.stays && observed.stays ||
        (direction == 1) && (cat == N) && cat.becomes(cat - 1) && direction.becomes(-1) && observed.stays ||
        (direction == -1) && (cat > 1) && cat.becomes(cat - 1) && direction.stays && observed.stays ||
        (direction == -1) && (cat == 1) && cat.becomes(cat + 1) && direction.becomes(1) && observed.stays ||
        (cat == observed) && observed.becomes(observed + 1) && cat.stays && direction.stays ||
        (cat == observed) && (observed == N) && observed.becomes(1) && cat.stays && direction.stays
    }
}
