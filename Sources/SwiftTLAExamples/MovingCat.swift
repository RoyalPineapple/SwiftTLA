@_spi(Internal) import SwiftTLA

public enum MovingCatSpec {
    public static let cat = Var<Int>("cat")
    public static let observed = Var<Int>("observed")
    public static let direction = Var<Int>("direction")
    public static let N = 6
    public static let spec = TLASpec("MovingCat") {
        Variable(cat, 3); Variable(observed, 3); Variable(direction, 1)
        Action("Move") {
            let goRight: ActionExpr = (direction == 1) && (cat < N) && (cat.prime == cat + 1) && (direction.prime == direction) && (observed.prime == observed)
            let goLeft: ActionExpr = (direction == 1) && (cat == N) && (cat.prime == cat - 1) && (direction.prime == -1) && (observed.prime == observed)
            let contLeft: ActionExpr = (direction == -1) && (cat > 1) && (cat.prime == cat - 1) && (direction.prime == direction) && (observed.prime == observed)
            let bounceRight: ActionExpr = (direction == -1) && (cat == 1) && (cat.prime == cat + 1) && (direction.prime == 1) && (observed.prime == observed)
            let observe: ActionExpr = (cat == observed) && (observed.prime == observed + 1) && (cat.prime == cat) && (direction.prime == direction)
            let observeWrap: ActionExpr = (cat == observed) && (observed == N) && (observed.prime == 1) && (cat.prime == cat) && (direction.prime == direction)
            goRight || goLeft || contLeft || bounceRight || observe || observeWrap
        }
    }
}
