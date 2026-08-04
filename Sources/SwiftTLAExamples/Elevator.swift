@_spi(Internal) import SwiftTLA
public enum ElevatorSpec {
    public static let floor = Var<Int>("floor"); public static let dir = Var<Int>("dir")
    public static let spec = TLASpec("Elevator") {
        Variable(floor, 1); Variable(dir, 1)
        Action("Up") { (floor < 5) && ((dir == 1) || (floor == 1)) && floor.prime == floor + 1 && dir.prime == 1 }
        Action("Down") { (floor > 1) && ((dir == -1) || (floor == 5)) && floor.prime == floor - 1 && dir.prime == -1 }
        Invariant("InBounds") { floor >= 1 && floor <= 5 }
    }
}
