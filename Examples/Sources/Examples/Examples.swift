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
        .init(name: "HourClock", spec: HourClock.spec, expectedStates: 12, source: "https://lamport.azurewebsites.net/tla/book.html", about: "A clock that ticks from 1 to 12 and wraps. Chapter 2 of Specifying Systems."),
        .init(name: "DieHard", spec: DieHard.spec, expectedStates: 16, source: "https://github.com/tlaplus/Examples/tree/master/specifications/DieHard", about: "Measure exactly 4 gallons using 3 and 5 gallon jugs."),
        .init(name: "CoffeeCan", spec: CoffeeCan.spec, expectedStates: 0, source: "https://github.com/tlaplus/Examples/tree/master/specifications/CoffeeCan", about: "Remove beans from a can. Parity of white beans never changes."),
        .init(name: "MovingCat", spec: MovingCat.spec, expectedStates: 24, source: "https://github.com/tlaplus/Examples/tree/master/specifications/Moving_Cat_Puzzle", about: "A cat bounces between boxes."),
        .init(name: "Majority", spec: Majority.spec, expectedStates: 0, source: "https://github.com/tlaplus/Examples/tree/master/specifications/Majority", about: "Boyer-Moore majority vote."),
        .init(name: "BoundedCounter", spec: BoundedCounter.spec, expectedStates: 7, source: "internal", about: "A counter that stays within bounds."),
        .init(name: "Toggle", spec: Toggle.spec, expectedStates: 2, source: "internal", about: "A simple on/off toggle."),
        .init(name: "BoolToggle", spec: BoolToggle.spec, expectedStates: 2, source: "internal", about: "A boolean toggle. First Bool example."),
        .init(name: "ThreeState", spec: ThreeState.spec, expectedStates: 3, source: "internal", about: "A three-state loop."),
        .init(name: "Bridge", spec: Bridge.spec, expectedStates: 12, source: "internal", about: "A single-lane bridge."),
        .init(name: "Lock", spec: Lock.spec, expectedStates: 2, source: "internal", about: "A binary lock."),
        .init(name: "Fibonacci", spec: Fibonacci.spec, expectedStates: 5, source: "internal", about: "Fibonacci sequence."),
        .init(name: "PingPong", spec: PingPong.spec, expectedStates: 2, source: "internal", about: "Ping pong."),
        .init(name: "Database", spec: Database.spec, expectedStates: 0, source: "internal", about: "Write-lock-unlock cycle."),
        .init(name: "Elevator", spec: Elevator.spec, expectedStates: 5, source: "internal", about: "An elevator moving between floors."),
        .init(name: "Traffic", spec: Traffic.spec, expectedStates: 3, source: "internal", about: "A traffic light."),
        .init(name: "Buffer", spec: Buffer.spec, expectedStates: 2, source: "internal", about: "A single-slot buffer."),
    ]
}
