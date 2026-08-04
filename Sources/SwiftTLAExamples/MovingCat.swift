@_spi(Internal) import SwiftTLA

public enum MovingCatSpec {
    public static let cat = Var<Int>("cat")
    public static let observed = Var<Int>("observed")
    public static let direction = Var<Int>("direction")
    public static let N = 6
    public static let spec = TLASpec("MovingCat") {
        Variable(cat, 3); Variable(observed, 3); Variable(direction, 1)
        Action("Move") {
            let goRight: ActionExpr = (direction == 1) && (cat < N) && (cat.next == cat + 1) && (direction.next == direction) && (observed.next == observed)
            let goLeft: ActionExpr = (direction == 1) && (cat == N) && (cat.next == cat - 1) && (direction.next == -1) && (observed.next == observed)
            let contLeft: ActionExpr = (direction == -1) && (cat > 1) && (cat.next == cat - 1) && (direction.next == direction) && (observed.next == observed)
            let bounceRight: ActionExpr = (direction == -1) && (cat == 1) && (cat.next == cat + 1) && (direction.next == 1) && (observed.next == observed)
            let observe: ActionExpr = (cat == observed) && (observed.next == observed + 1) && (cat.next == cat) && (direction.next == direction)
            let observeWrap: ActionExpr = (cat == observed) && (observed == N) && (observed.next == 1) && (cat.next == cat) && (direction.next == direction)
            goRight || goLeft || contLeft || bounceRight || observe || observeWrap
        }
    }
}
