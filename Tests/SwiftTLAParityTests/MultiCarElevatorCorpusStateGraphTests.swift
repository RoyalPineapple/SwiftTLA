import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct MultiCarElevatorCorpusStateGraphTests {
    @Test("MultiCarElevator native execution preserves the complete bounded formal graph")
    func nativeGraphMatchesFormalGraph() throws {
        let compilation = try MultiCarElevator.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try runtime.initialStates()
        let machine = try MultiCarElevator.makeMachine()
        try #require(initial.count == 1)
        #expect(try formalProjection(of: machine.state) == initial[0].projection(using: compilation.layout))
        let names = Dictionary(uniqueKeysWithValues: compilation.layout.actions.map { ($0.id, $0.declaration.name) })
        var pending = [(initial[0], machine)]
        var visited: Set<CompiledState> = []
        var nativeStates: Set<MultiCarElevator.State> = []
        let actions = allActions()
        #expect(Set(actions).count == 80)
        while let (state, machine) = pending.popLast() {
            guard visited.insert(state).inserted else { continue }
            try #require(visited.count <= 4_000, "Execution escaped the bounded elevator scenario")
            #expect(nativeStates.insert(machine.state).inserted)
            let successors = try runtime.successors(from: state)
            let expected = try Dictionary(grouping: successors) { successor in
                try TLAValue.tuple([.string(#require(names[successor.action]))]
                    + successor.arguments.map { try $0.rendered(using: compilation.layout) })
            }
            let enabled = try machine.enabledActions()
            #expect(Set(enabled.map(signature)) == Set(expected.keys))
            let violations = try compilation.semantics.behavior.invariants.filter {
                try !runtime.invariantHolds($0, in: state)
            }.map(\.name)
            #expect(try machine.violatedInvariants() == violations)
            for action in actions {
                var next = machine
                let candidates = expected[signature(action)] ?? []
                #expect(try machine.isEnabled(action) == !candidates.isEmpty)
                guard let successor = candidates.first else {
                    #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try next.send(action) }
                    #expect(next.state == machine.state)
                    continue
                }
                try #require(candidates.count == 1, "Each parameterized elevator action is deterministic")
                let transition = try next.send(action)
                #expect(transition.before == machine.state)
                #expect(transition.after == next.state)
                #expect(try formalProjection(of: next.state) == successor.state.projection(using: compilation.layout))
                pending.append((successor.state, next))
            }
        }
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: .init(maximumStateLimit: 4_000, symmetryReduction: .disabled)
        ).explore()
        try #require(exploration.isComplete)
        #expect(visited.count == exploration.graph.states.count)
        #expect(nativeStates.count == visited.count)
    }

    private func allActions() -> [MultiCarElevator.Action] {
        var actions: [MultiCarElevator.Action] = []
        for person in MultiCarElevator.PersonID.allCases {
            for floor in MultiCarElevator.FloorID.allCases {
                for direction in MultiCarElevator.Direction.allCases {
                    actions.append(.request(person: person, floor: floor, direction: direction))
                }
                for car in MultiCarElevator.CarID.allCases {
                    actions.append(.board(person: person, car: car, floor: floor))
                    actions.append(.completeRide(person: person, car: car, floor: floor))
                }
            }
            for car in MultiCarElevator.CarID.allCases {
                for direction in MultiCarElevator.Direction.allCases {
                    actions.append(.assign(person: person, car: car, direction: direction))
                }
            }
        }
        for car in MultiCarElevator.CarID.allCases {
            for floor in MultiCarElevator.FloorID.allCases {
                for direction in MultiCarElevator.Direction.allCases {
                    actions.append(.move(car: car, direction: direction, floor: floor))
                    actions.append(.openDoor(car: car, floor: floor, direction: direction))
                    actions.append(.closeDoor(car: car, floor: floor, direction: direction))
                }
            }
        }
        return actions
    }

    private func signature(_ action: MultiCarElevator.Action) -> TLAValue {
        switch action {
        case .request(let person, let floor, let direction):
            .tuple([.string("request"), person.tlaValue, floor.tlaValue, direction.tlaValue])
        case .assign(let person, let car, let direction):
            .tuple([.string("assign"), person.tlaValue, car.tlaValue, direction.tlaValue])
        case .move(let car, let direction, let floor):
            .tuple([.string("move"), car.tlaValue, direction.tlaValue, floor.tlaValue])
        case .openDoor(let car, let floor, let direction):
            .tuple([.string("openDoor"), car.tlaValue, floor.tlaValue, direction.tlaValue])
        case .board(let person, let car, let floor):
            .tuple([.string("board"), person.tlaValue, car.tlaValue, floor.tlaValue])
        case .closeDoor(let car, let floor, let direction):
            .tuple([.string("closeDoor"), car.tlaValue, floor.tlaValue, direction.tlaValue])
        case .completeRide(let person, let car, let floor):
            .tuple([.string("completeRide"), person.tlaValue, car.tlaValue, floor.tlaValue])
        }
    }

    private func formalProjection(of state: MultiCarElevator.State) throws -> TLAStateProjection {
        let fields: [(String, TLAValue)] = [
            ("cars", .function(Dictionary(uniqueKeysWithValues: state.cars.map { key, car in
                (key.tlaValue, .record(["floor": car.floor.tlaValue,
                    "doorsOpen": .bool(car.doorsOpen), "rider": .string(car.rider)]))
            }))),
            ("calls", .set(Set(state.calls.map { call in
                .record(["person": call.person.tlaValue, "floor": call.floor.tlaValue,
                    "direction": call.direction.tlaValue])
            }))),
            ("lastMoveDoorClosed", .bool(state.lastMoveDoorClosed))
        ]
        return try TLAStateProjection(validating: fields.map { name, value in
            .init(token: try #require(TLAStateProjection.Token(validating: name)), value: value)
        })
    }
}
