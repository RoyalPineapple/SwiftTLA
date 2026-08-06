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
        .init(name: "MissionariesAndCannibals", spec: MissionariesAndCannibals.spec, expectedStates: 0, source: "specifications/MissionariesAndCannibals", about: "Classic river crossing puzzle with state constraints."),
        .init(name: "CarTalkPuzzle", spec: CarTalkPuzzle.spec, expectedStates: 0, source: "specifications/CarTalkPuzzle", about: "Number puzzle from the Car Talk radio show."),
        .init(name: "Prisoners", spec: Prisoners.spec, expectedStates: 0, source: "specifications/Prisoners", about: "100 prisoners and a light bulb coordination problem."),
        .init(name: "CarTalkPuzzle", spec: CarTalkPuzzle.spec, expectedStates: 0, source: "specifications/CarTalkPuzzle", about: "Number puzzle from Car Talk."),
        .init(name: "Prisoners", spec: Prisoners.spec, expectedStates: 0, source: "specifications/Prisoners", about: "Prisoners and light bulb."),
        .init(name: "MultiPaxos", spec: MultiPaxos.spec, expectedStates: 0, source: "specifications/MultiPaxos", about: "Consensus with quorum acceptance."),
        .init(name: "NQueens", spec: NQueens.spec, expectedStates: 0, source: "specifications/NQueens", about: "N-Queens puzzle."),
        .init(name: "GameOfLife", spec: GameOfLife.spec, expectedStates: 0, source: "specifications/GameOfLife", about: "Cellular automaton."),
        .init(name: "Stones", spec: Stones.spec, expectedStates: 0, source: "specifications/Stones", about: "Take-away game."),
        .init(name: "TortoiseHare", spec: TortoiseHare.spec, expectedStates: 0, source: "specifications/TortoiseHare", about: "Floyd's cycle detection algorithm."),
        .init(name: "SlidingPuzzles", spec: SlidingPuzzles.spec, expectedStates: 0, source: "specifications/SlidingPuzzles", about: "15-puzzle sliding tile problem."),
        .init(name: "SingleLaneBridge", spec: SingleLaneBridge.spec, expectedStates: 0, source: "specifications/SingleLaneBridge", about: "Traffic coordination on a one-lane bridge."),
        .init(name: "ReadersWriters", spec: ReadersWriters.spec, expectedStates: 0, source: "specifications/ReadersWriters", about: "Classic readers-writers concurrency pattern."),
        .init(name: "TransitiveClosure", spec: TransitiveClosure.spec, expectedStates: 0, source: "specifications/TransitiveClosure", about: "Graph reachability via transitive closure."),
        .init(name: "Termination", spec: Termination.spec, expectedStates: 0, source: "specifications/Termination", about: "Proof of program termination."),
        .init(name: "Paxos", spec: Paxos.spec, expectedStates: 0, source: "specifications/Paxos", about: "Distributed consensus with record-based messages."),
        .init(name: "Bakery", spec: Bakery.spec, expectedStates: 0, source: "specifications/Bakery-Boulangerie", about: "Lamport's mutual exclusion algorithm for concurrent actors."),
        .init(name: "DiningPhilosophers", spec: DiningPhilosophers.spec, expectedStates: 0, source: "specifications/DiningPhilosophers", about: "Deadlock avoidance in concurrent resource acquisition."),
        .init(name: "Allocator", spec: Allocator.spec, expectedStates: 4, source: "specifications/allocator", about: "Resource allocator."),
    ]
}
