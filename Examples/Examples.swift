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
        .init(name: "HourClock", spec: HourClock.spec, expectedStates: 12, source: "https://lamport.azurewebsites.net/tla/book.html", about: "A clock that ticks from 1 to 12. Chapter 2 of Specifying Systems."),
        .init(name: "DieHard", spec: DieHard.spec, expectedStates: 16, source: "https://github.com/tlaplus/Examples/tree/master/specifications/DieHard", about: "Measure exactly 4 gallons using 3 and 5 gallon jugs."),
        .init(name: "CoffeeCan", spec: CoffeeCan.spec, expectedStates: 0, source: "https://github.com/tlaplus/Examples/tree/master/specifications/CoffeeCan", about: "Remove beans from a can. Parity of white beans never changes."),
        .init(name: "MovingCat", spec: MovingCat.spec, expectedStates: 24, source: "https://github.com/tlaplus/Examples/tree/master/specifications/Moving_Cat_Puzzle", about: "A cat bounces between boxes."),
        .init(name: "Majority", spec: Majority.spec, expectedStates: 0, source: "https://github.com/tlaplus/Examples/tree/master/specifications/Majority", about: "Boyer-Moore majority vote."),
    ]
}
