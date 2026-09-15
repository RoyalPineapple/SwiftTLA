import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ElevatorBankDemoTests {
    @Test("Elevator bank machine boards, moves, and exits one rider")
    func machineBoardsMovesAndExits() throws {
        var machine = try ElevatorBank.makeMachine()
        #expect(machine.state.cars[.carA]?.floor == .one)
        #expect(machine.state.cars[.carA]?.door == .closed)
        #expect(machine.state.cars[.carA]?.rider == ElevatorBank.Rider.none)
        #expect(machine.state.riders[.alice]?.phase == .waiting)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.door == .open)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.door == .closed)
        #expect(machine.state.cars[.carA]?.rider == .alice)
        #expect(machine.state.riders[.alice]?.phase == .onboard)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.floor == .two)
        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.floor == .three)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.door == .open)
        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.rider == ElevatorBank.Rider.none)
        #expect(machine.state.cars[.carA]?.door == .closed)
        #expect(machine.state.riders[.alice]?.phase == .arrived)
    }
}
