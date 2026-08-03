import SwiftTLA

struct CoffeeCanExample {
    static let maxBeans = 5
    static let black = Var<Int>("black")
    static let white = Var<Int>("white")
    static let spec = TLASpec("CoffeeCan") {
        Variable(black, maxBeans)
        Variable(white, maxBeans)
        Act("RemoveTwoBlack") { (black >= 2) && (next(black) == black - 1) && (next(white) == white) }
        Act("RemoveTwoWhite") { (white >= 2) && (next(white) == white - 2) && (next(black) == black + 1) }
        Act("RemoveOneEach") { (black >= 1) && (white >= 1) && (next(white) == white - 1) && (next(black) == black) }
    }
}
