import SwiftTLA

public struct ExampleDescription: Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let spec: TLASpec
    public let expectedStates: Int
    public let source: String
    
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: ExampleDescription, rhs: ExampleDescription) -> Bool { lhs.name == rhs.name }
}

public enum Examples {
    public static let all: [ExampleDescription] = [
        ExampleDescription(name: "HourClock", spec: HourClockSpec.spec, expectedStates: 12,
            source: "https://lamport.azurewebsites.net/tla/book.html"),
        ExampleDescription(name: "DieHard", spec: DieHardSpec.spec, expectedStates: 16,
            source: "https://github.com/tlaplus/Examples/tree/master/specifications/DieHard"),
        ExampleDescription(name: "CoffeeCan", spec: CoffeeCanSpec.spec, expectedStates: 0,
            source: "https://github.com/tlaplus/Examples/tree/master/specifications/CoffeeCan"),
        ExampleDescription(name: "MovingCat", spec: MovingCatSpec.spec, expectedStates: 24,
            source: "https://github.com/tlaplus/Examples/tree/master/specifications/Moving_Cat_Puzzle"),
        ExampleDescription(name: "Majority", spec: MajorSpec.spec, expectedStates: 0,
            source: "https://github.com/tlaplus/Examples/tree/master/specifications/Major"),
        ExampleDescription(name: "BoundedCounter", spec: BoundedCounterSpec.spec, expectedStates: 7,
            source: "https://github.com/tlaplus/Examples/tree/master/specifications/SpecifyingSystems"),
        ExampleDescription(name: "Toggle", spec: ToggleSpec.spec, expectedStates: 2,
            source: "internal"),
        ExampleDescription(name: "ThreeState", spec: ThreeStateSpec.spec, expectedStates: 3,
            source: "internal"),
    ]
}
