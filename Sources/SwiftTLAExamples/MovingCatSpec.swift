import SwiftTLA

public enum MovingCatSpec {
    public static let cat = Var<Int>("cat")
    public static let observed = Var<Int>("observed")
    public static let direction = Var<Int>("direction")
    public static let N = 6

    public static let spec = TLASpec("MovingCat") {
        Variable(cat, 3)
        Variable(observed, 3)
        Variable(direction, 1)
        Act("Move") {
            let goRight: ActionExpr = (direction == 1) && (cat < N) && (next(cat) == cat + 1) && (next(direction) == direction) && (next(observed) == observed)
            let goLeft: ActionExpr = (direction == 1) && (cat == N) && (next(cat) == cat - 1) && (next(direction) == -1) && (next(observed) == observed)
            let contLeft: ActionExpr = (direction == -1) && (cat > 1) && (next(cat) == cat - 1) && (next(direction) == direction) && (next(observed) == observed)
            let goRight2: ActionExpr = (direction == -1) && (cat == 1) && (next(cat) == cat + 1) && (next(direction) == 1) && (next(observed) == observed)
            let observe: ActionExpr = (cat == observed) && (next(observed) == observed + 1) && (next(cat) == cat) && (next(direction) == direction)
            let observeWrap: ActionExpr = (cat == observed) && (observed == N) && (next(observed) == 1) && (next(cat) == cat) && (next(direction) == direction)
            goRight || goLeft || contLeft || goRight2 || observe || observeWrap
        }
    }
    public static let expectedStates = 24
}
