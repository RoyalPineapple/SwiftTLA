import SwiftTLA

public struct ExampleDescription: Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let spec: TLASpec
    public let expectedStates: Int
    public let source: String
    public let about: String
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
    public static func == (lhs: ExampleDescription, rhs: ExampleDescription) -> Bool { lhs.name == rhs.name }
}

public enum Examples {
    public static let all: [ExampleDescription] = [
        .init(name: "HourClock", spec: HourClock.spec, expectedStates: 12, source: "SpecifyingSystems", about: "Clock ticking 1-12."),
        .init(name: "DieHard", spec: DieHard.spec, expectedStates: 16, source: "specifications/DieHard", about: "Measure 4 gallons with 3 and 5 gallon jugs."),
        .init(name: "CoffeeCan", spec: CoffeeCan.spec, expectedStates: 36, source: "specifications/CoffeeCan", about: "Bean removal puzzle."),
        .init(name: "MovingCat", spec: MovingCat.spec, expectedStates: 70, source: "specifications/Moving_Cat_Puzzle", about: "Cat bouncing between boxes."),
        .init(name: "Majority", spec: Majority.spec, expectedStates: 5, source: "specifications/Majority", about: "Boyer-Moore majority vote."),
        .init(name: "SumsEven", spec: SumsEven.spec, expectedStates: 0, source: "specifications/sums_even", about: "Proof that x+x is always even."),
        .init(name: "Allocator", spec: Allocator.spec, expectedStates: 4, source: "specifications/allocator", about: "Resource allocator."),
    ]
}
