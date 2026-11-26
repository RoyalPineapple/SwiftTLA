import SwiftTLA
import Testing
@testable import UpstreamParity

struct ElevatorBoardingTests {
    @Test("One EnterElevator action boards everyone waiting at the floor in that direction")
    func boardsBothRiders() throws {
        let configuration = try MultiCarElevator.Configuration(
            Person: [.p1, .p2], Elevator: [.e1, .e2], FloorCount: 2)
        let initial = try MultiCarElevator.initialMachines(configuration: configuration)
        #expect(initial.count == 64)
        var machine = try #require(initial.first { machine in
            machine.state.PersonState.values.allSatisfy { $0.location == .first(1) && $0.destination == 2 }
                && machine.state.ElevatorState[.e1]?.floor == 1
                && machine.state.ElevatorState[.e2]?.floor == 2
        })
        _ = try machine.send(.CallElevator(p: .p1))
        _ = try machine.send(.CallElevator(p: .p2))
        _ = try machine.send(.DispatchElevator(c: .init(floor: 1, direction: "Up")))
        _ = try machine.send(.OpenElevatorDoors(e: .e1))
        #expect(try !machine.isEnabled(.CloseElevatorDoors(e: .e1)))
        _ = try machine.send(.EnterElevator(e: .e1))
        #expect(machine.state.PersonState[.p1]?.location == .second(.e1))
        #expect(machine.state.PersonState[.p2]?.location == .second(.e1))
        #expect(machine.state.ElevatorState[.e1]?.buttonsPressed == [2])
        #expect(try machine.isEnabled(.CloseElevatorDoors(e: .e1)))
    }
}
