import SwiftTLA

extension Example {
    package static let coffeeCanMax5 = FiniteModelFixture(
        expectedDistinct: 20,
        maximumStateLimit: 50_000,
        spec: coffeeCanSpec(maxBeanCount: 5),
    )

}
