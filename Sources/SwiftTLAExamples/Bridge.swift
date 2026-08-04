import SwiftTLA
public enum BridgeSpec {
    public static let cars = Var<Int>("cars"); public static let dir = Var<Int>("dir")
    public static let spec = TLASpec("Bridge") {
        Variable(cars, 0); Variable(dir, 0)
        Action("Enter") { (cars < 3) && (cars.next == cars + 1) && (dir.next == dir) && (dir == dir) }
        Action("Leave") { (cars > 0) && (cars.next == cars - 1) && (dir.next == dir) }
        Action("Switch") { (cars == 0) && (dir.next == (dir + 1) % 2) && (cars.next == cars) }
        Invariant("Max3") { cars <= 3 }
    }
}
