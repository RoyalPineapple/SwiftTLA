import SwiftTLA

public struct ExampleDescription: Hashable, Identifiable {
    public var id: String { name }
    public let name: String; public let spec: TLASpec; public let expectedStates: Int
    public let source: String; public let about: String
    public func hash(into h: inout Hasher) { h.combine(name) }
    public static func ==(a:ExampleDescription,b:ExampleDescription)->Bool{a.name==b.name}
}

public enum Examples {
    public static let all: [ExampleDescription] = [
        ExampleDescription(name:"HourClock",spec:HourClockSpec.spec,expectedStates:12,source:"https://lamport.azurewebsites.net/tla/book.html",about:"A clock that ticks from 1 to 12 and wraps. Chapter 2 of Specifying Systems."),
        ExampleDescription(name:"DieHard",spec:DieHardSpec.spec,expectedStates:16,source:"https://github.com/tlaplus/Examples/tree/master/specifications/DieHard",about:"Measure exactly 4 gallons using 3 and 5 gallon jugs. Classic puzzle."),
        ExampleDescription(name:"CoffeeCan",spec:CoffeeCanSpec.spec,expectedStates:0,source:"https://github.com/tlaplus/Examples/tree/master/specifications/CoffeeCan",about:"Remove beans from a can. Parity of white beans never changes."),
        ExampleDescription(name:"MovingCat",spec:MovingCatSpec.spec,expectedStates:24,source:"https://github.com/tlaplus/Examples/tree/master/specifications/Moving_Cat_Puzzle",about:"A cat bounces between boxes. Each box must be observed exactly once."),
        ExampleDescription(name:"Majority",spec:MajorSpec.spec,expectedStates:0,source:"https://github.com/tlaplus/Examples/tree/master/specifications/Major",about:"Boyer-Moore majority vote. Find the element that appears more than half the time."),
        ExampleDescription(name:"BoundedCounter",spec:BoundedCounterSpec.spec,expectedStates:7,source:"internal",about:"A counter that stays within bounds -3…3. The invariant is checked at every state."),
        ExampleDescription(name:"Toggle",spec:ToggleSpec.spec,expectedStates:2,source:"internal",about:"A simple on/off toggle. Two states, one action. No invariants needed."),
        ExampleDescription(name:"ThreeState",spec:ThreeStateSpec.spec,expectedStates:3,source:"internal",about:"A three-state loop: 0→1→2→0. Demonstrates cyclic state machines."),
        ExampleDescription(name:"Bridge",spec:BridgeSpec.spec,expectedStates:12,source:"internal",about:"A single-lane bridge. Never more than 3 cars. Direction switches when empty."),
        ExampleDescription(name:"Lock",spec:LockSpec.spec,expectedStates:2,source:"internal",about:"A binary lock. Only locks when unlocked, unlocks when locked."),
        ExampleDescription(name:"Fibonacci",spec:FibSpec.spec,expectedStates:5,source:"internal",about:"Fibonacci sequence: each step shifts a,b and computes the next term."),
        ExampleDescription(name:"PingPong",spec:PingPongSpec.spec,expectedStates:2,source:"internal",about:"Ping pong: two states trading back and forth."),
        ExampleDescription(name:"Database",spec:DatabaseSpec.spec,expectedStates:0,source:"internal",about:"Write-lock-unlock cycle. Data only changes when unlocked."),
        ExampleDescription(name:"Elevator",spec:ElevatorSpec.spec,expectedStates:5,source:"internal",about:"An elevator moving between floors 1-5. Changes direction at ends."),
        ExampleDescription(name:"Traffic",spec:TrafficSpec.spec,expectedStates:3,source:"internal",about:"A traffic light cycling green→yellow→red. Three states."),
        ExampleDescription(name:"Buffer",spec:BufferSpec.spec,expectedStates:2,source:"internal",about:"A single-slot buffer. Put when empty, Get when full."),
    ]
}
