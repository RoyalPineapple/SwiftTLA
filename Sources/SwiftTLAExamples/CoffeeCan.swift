@_spi(Internal) import SwiftTLA

public enum CoffeeCanSpec {
    public static let black = Var<Int>("black")
    public static let white = Var<Int>("white")
    public static let maxBeans = 5
    public static let spec = TLASpec("CoffeeCan") {
        Variable(black, maxBeans); Variable(white, maxBeans)
        Action("BB") { (black >= 2) && (black.prime == black - 1) && (white.prime == white) }
        Action("WW") { (white >= 2) && (white.prime == white - 2) && (black.prime == black + 1) }
        Action("BW") { (black >= 1) && (white >= 1) && (white.prime == white - 1) && (black.prime == black) }
    }
}
