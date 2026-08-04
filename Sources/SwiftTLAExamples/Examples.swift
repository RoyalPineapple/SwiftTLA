import SwiftTLA

public struct ExampleDescription: Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let spec: TLASpec
    public let expectedStates: Int
    
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: ExampleDescription, rhs: ExampleDescription) -> Bool { lhs.name == rhs.name }
}

public enum Examples {
    public static let all: [ExampleDescription] = [
        ExampleDescription(name: "HourClock", spec: HourClockSpec.spec, expectedStates: 12),
        ExampleDescription(name: "DieHard", spec: DieHardSpec.spec, expectedStates: 16),
        ExampleDescription(name: "CoffeeCan", spec: CoffeeCanSpec.spec, expectedStates: 0),
    ]
}
