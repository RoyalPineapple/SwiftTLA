@_spi(Internal) import SwiftTLA

public enum CoffeeCanSpec {
    public static let black = Var<Int>("black")
    public static let white = Var<Int>("white")
    public static let maxBeans = 5
    public static let spec = TLASpec("CoffeeCan") {
        Variable(black, maxBeans); Variable(white, maxBeans)
        Action("BB") { (black >= 2) && (black.next == black - 1) && (white.next == white) }
        Action("WW") { (white >= 2) && (white.next == white - 2) && (black.next == black + 1) }
        Action("BW") { (black >= 1) && (white >= 1) && (white.next == white - 1) && (black.next == black) }
    }
}
