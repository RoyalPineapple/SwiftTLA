import SwiftTLA
import SwiftTLAMacros

private struct CoffeeCanFields {
    let black: Int
    let white: Int
}

private enum CoffeeCanSchema: TLARecordSchema {
    typealias Fields = CoffeeCanFields

    static let fields: [TLARecordFieldDeclaration<Self>] = [
        .init(black, default: 0),
        .init(white, default: 0),
    ]

    static func fieldName<Value>(for field: KeyPath<CoffeeCanFields, Value>) -> String? {
        let key = field as AnyKeyPath
        if key == \CoffeeCanFields.black { return "black" }
        if key == \CoffeeCanFields.white { return "white" }
        return nil
    }

    static let black = field(\CoffeeCanFields.black)
    static let white = field(\CoffeeCanFields.white)
}

private typealias CoffeeCan = Record<CoffeeCanSchema>

private func coffeeCanDomain(maximumBeanCount: Int) -> Expr<SetExpr<CoffeeCan>> {
    let cans = (0...maximumBeanCount).flatMap { black in
        (0...maximumBeanCount).compactMap { white -> StateExpr? in
            guard (1...maximumBeanCount).contains(black + white) else { return nil }
            return CoffeeCan.literal(
                .init(CoffeeCanSchema.black, black),
                .init(CoffeeCanSchema.white, white)
            ).raw
        }
    }
    return Expr(.setLiteral(cans))
}

func coffeeCanSpec(maxBeanCount: Int) -> TLASpec {
    let can = Var<CoffeeCan>("can")
    let black = can[CoffeeCanSchema.black]
    let white = can[CoffeeCanSchema.white]

    return #spec("CoffeeCan") {
        Extends(.naturals)
        Variable(can, in: coffeeCanDomain(maximumBeanCount: maxBeanCount))
        SwiftTLA.Action("PickSameColorBlack") {
            black + white > 1
                && black >= 2
                && can.becomes(can.updating(CoffeeCanSchema.black, to: black - 1))
        }
        SwiftTLA.Action("PickSameColorWhite") {
            black + white > 1
                && white >= 2
                && can.becomes(can
                    .updating(CoffeeCanSchema.black, to: black + 1)
                    .updating(CoffeeCanSchema.white, to: white - 2))
        }
        SwiftTLA.Action("PickDifferentColor") {
            black + white > 1
                && black >= 1
                && white >= 1
                && can.becomes(can.updating(CoffeeCanSchema.black, to: black - 1))
        }
        SwiftTLA.Action("Termination") {
            black + white == 1
        }
        Invariant("TypeInvariant") {
            black >= 0 && black <= maxBeanCount
                && white >= 0 && white <= maxBeanCount
        }
    }
}
