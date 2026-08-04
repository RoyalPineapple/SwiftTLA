import SwiftTLA

public struct Example {
    public let name: String
    public let spec: TLASpec
    public let expectedStates: Int
}

public enum Examples {
    public static let all: [Example] = [
        Example(name: "HourClock", spec: HourClockSpec.spec, expectedStates: 12),
        Example(name: "DieHard", spec: DieHardSpec.spec, expectedStates: 16),
        Example(name: "CoffeeCan", spec: CoffeeCanSpec.spec, expectedStates: 0),
    ]
}
