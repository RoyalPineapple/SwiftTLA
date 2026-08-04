import SwiftTLA

public struct ExampleDescription {
    public let name: String
    public let spec: TLASpec
    public let expectedStates: Int
}

public enum Examples {
    public static let all: [ExampleDescription] = [
        ExampleDescription(name: "HourClock", spec: HourClockSpec.spec, expectedStates: 12),
        ExampleDescription(name: "DieHard", spec: DieHardSpec.spec, expectedStates: 16),
        ExampleDescription(name: "CoffeeCan", spec: CoffeeCanSpec.spec, expectedStates: 0),
    ]
}
