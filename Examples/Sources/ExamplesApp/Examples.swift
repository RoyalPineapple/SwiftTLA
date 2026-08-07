import ExamplesLibrary
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
        .init(name: "CoffeeCan", spec: CoffeeCan.spec, expectedStates: 20, source: "specifications/CoffeeCan", about: "Bean can (MaxBeanCount=5, upstream shape)."),
        .init(name: "MovingCat", spec: MovingCat.spec, expectedStates: 48, source: "specifications/Moving_Cat_Puzzle", about: "Cat hunt, 6 boxes (CatEvenBoxes)."),
        .init(name: "Majority", spec: Majority.spec, expectedStates: 5, source: "specifications/Majority", about: "Boyer-Moore majority vote."),
        .init(name: "SumsEven", spec: SumsEven.spec, expectedStates: 0, source: "specifications/sums_even", about: "Proof that x+x is always even."),
        .init(name: "MissionariesAndCannibals", spec: MissionariesAndCannibals.spec, expectedStates: 0, source: "specifications/MissionariesAndCannibals", about: "Classic river crossing puzzle."),
        .init(name: "MultiPaxos", spec: MultiPaxos.spec, expectedStates: 0, source: "specifications/MultiPaxos", about: "Consensus with quorum acceptance."),
        .init(name: "Stones", spec: Stones.spec, expectedStates: 0, source: "specifications/Stones", about: "Take-away game."),
        .init(name: "TortoiseHare", spec: TortoiseHare.spec, expectedStates: 0, source: "specifications/TortoiseHare", about: "Floyd cycle detection."),
        .init(name: "Paxos", spec: Paxos.spec, expectedStates: 0, source: "specifications/Paxos", about: "Simplified consensus sketch (not full Paxos)."),
        .init(name: "Bakery", spec: Bakery.spec, expectedStates: 0, source: "specifications/Bakery-Boulangerie", about: "Lamport mutual exclusion sketch."),
        .init(name: "DiningPhilosophers", spec: DiningPhilosophers.spec, expectedStates: 0, source: "specifications/DiningPhilosophers", about: "Resource acquisition sketch."),
        .init(name: "Allocator", spec: Allocator.spec, expectedStates: 400, source: "specifications/allocator", about: "SimpleAllocator (Merz): 3 clients, 2 resources.")
    ]
}
