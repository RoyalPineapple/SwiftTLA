import SwiftTLA

/// CoffeeCan — MaxBeanCount=5, upstream record shape.
/// (Not @TLAModel: init set is built in Swift before the builder.)
public struct CoffeeCan {
    public static var spec: TLASpec {
        ParityCatalog_CoffeeCan.max5
    }
}

/// Local builder (Examples package cannot depend on UpstreamParity without a product).
enum ParityCatalog_CoffeeCan {
    static var max5: TLASpec {
        let maxBeanCount = 5
        let can = Var<TLARecordType>("can")
        var cans: [TLAValue] = []
        for black in 0...maxBeanCount {
            for white in 0...maxBeanCount where (1...maxBeanCount).contains(black + white) {
                cans.append(.record(["black": .int(black), "white": .int(white)]))
            }
        }
        return TLASpec("CoffeeCan") {
            Extends("Naturals")
            Variable(can, in: cans)
            Action("PickSameColorBlack") {
                can.black + can.white > 1 && can.black >= 2
                    && can.becomes(can.updated(at: "black", to: can.black - 1))
            }
            Action("PickSameColorWhite") {
                can.black + can.white > 1 && can.white >= 2
                    && can.becomes(
                        StateExpr.except(
                            StateExpr.except(
                                .variable("can"),
                                .value(.string("black")),
                                can.black + 1
                            ),
                            .value(.string("white")),
                            can.white - 2
                        )
                    )
            }
            Action("PickDifferentColor") {
                can.black + can.white > 1 && can.black >= 1 && can.white >= 1
                    && can.becomes(can.updated(at: "black", to: can.black - 1))
            }
            Action("Termination") {
                can.black + can.white == 1
            }
            Invariant("TypeInvariant") {
                can.black >= 0 && can.black <= maxBeanCount
                    && can.white >= 0 && can.white <= maxBeanCount
            }
        }
    }
}
