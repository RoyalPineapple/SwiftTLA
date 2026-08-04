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
        ExampleDescription(name:"HourClock",spec:HourClock.spec,expectedStates:12,source:"https://lamport.azurewebsites.net/tla/book.html",about:"A clock that ticks from 1 to 12 and wraps."),
        ExampleDescription(name:"DieHard",spec:DieHard.spec,expectedStates:16,source:"https://github.com/tlaplus/Examples/tree/master/specifications/DieHard",about:"Measure exactly 4 gallons using 3 and 5 gallon jugs."),
        ExampleDescription(name:"CoffeeCan",spec:CoffeeCan.spec,expectedStates:0,source:"https://github.com/tlaplus/Examples/tree/master/specifications/CoffeeCan",about:"Remove beans from a can. Parity of white beans never changes."),
        ExampleDescription(name:"MovingCat",spec:MovingCat.spec,expectedStates:24,source:"https://github.com/tlaplus/Examples/tree/master/specifications/Moving_Cat_Puzzle",about:"A cat bounces between boxes."),
        ExampleDescription(name:"Majority",spec:Majority.spec,expectedStates:0,source:"https://github.com/tlaplus/Examples/tree/master/specifications/Majority",about:"Boyer-Moore majority vote."),
        ExampleDescription(name:"BoundedCounter",spec:BoundedCounter.spec,expectedStates:7,source:"internal",about:"A counter that stays within bounds -3\u{2026}3."),
        ExampleDescription(name:"Toggle",spec:Toggle.spec,expectedStates:2,source:"internal",about:"A simple on/off toggle."),
        ExampleDescription(name:"ThreeState",spec:ThreeState.spec,expectedStates:3,source:"internal",about:"A three-state loop."),
        ExampleDescription(name:"Bridge",spec:Bridge.spec,expectedStates:12,source:"internal",about:"A single-lane bridge."),
        ExampleDescription(name:"Lock",spec:Lock.spec,expectedStates:2,source:"internal",about:"A binary lock."),
        ExampleDescription(name:"Fibonacci",spec:Fibonacci.spec,expectedStates:5,source:"internal",about:"Fibonacci sequence."),
        ExampleDescription(name:"PingPong",spec:PingPong.spec,expectedStates:2,source:"internal",about:"Ping pong."),
        ExampleDescription(name:"Database",spec:Database.spec,expectedStates:0,source:"internal",about:"Write-lock-unlock cycle."),
        ExampleDescription(name:"Elevator",spec:Elevator.spec,expectedStates:5,source:"internal",about:"An elevator moving between floors."),
        ExampleDescription(name:"Traffic",spec:Traffic.spec,expectedStates:3,source:"internal",about:"A traffic light."),
        ExampleDescription(name:"Buffer",spec:Buffer.spec,expectedStates:2,source:"internal",about:"A single-slot buffer."),
    ]
}
