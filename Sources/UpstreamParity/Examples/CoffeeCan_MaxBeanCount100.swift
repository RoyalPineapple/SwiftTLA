import SwiftTLA

extension Example {
    // MARK: CoffeeCan MaxBeanCount=100 (same factory, scale up)

    static let coffeeCanMax100 = Example.Entry(
        id: "CoffeeCan/MaxBeanCount100",
        upstreamSpec: "CoffeeCan",
        upstreamModule: "specifications/CoffeeCan/CoffeeCan.tla",
        upstreamCfg: nil,
        expectedDistinct: 5150,
        expectedResult: "success",
        spec: coffeeCanSpec(maxBeanCount: 100),
        notes: "M=100. Same spec shape as M=5.",
        matchesUpstreamTLC: true
    )
}
