import SwiftTLA

extension Example {
    package static let coffeeCanMax5 = Entry(
        id: "CoffeeCan/MaxBeanCount5",
        upstreamSpec: "CoffeeCan",
        upstreamModule: "specifications/CoffeeCan/CoffeeCan.tla",
        upstreamCfg: nil,
        expectedDistinct: 20,
        maximumStateLimit: 50_000,
        spec: coffeeCanSpec(maxBeanCount: 5),
        notes: "Upstream shape (record can, all cans with 1..M beans). M=5 → 20 states. M=100 upstream = 5150 (same port, scale CONSTANT).",
    )

}
