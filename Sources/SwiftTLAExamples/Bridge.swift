@_spi(Internal) import SwiftTLA
public enum BridgeSpec {
    public static let cars = Var<Int>("cars"); public static let dir = Var<Int>("dir")
    public static let spec = TLASpec("Bridge") {
        Variable(cars, 0); Variable(dir, 0)
        Action("Enter") { (cars < 3) && (cars.prime == cars + 1) && (dir.prime == dir) && (dir == dir) }
        Action("Leave") { (cars > 0) && (cars.prime == cars - 1) && (dir.prime == dir) }
        Action("Switch") { (cars == 0) && (dir.prime == (dir + 1) % 2) && (cars.prime == cars) }
        Invariant("Max3") { cars <= 3 }
    }
}
