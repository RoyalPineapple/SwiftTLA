import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ElevatorBankDemoTests {
    @Test("Elevator bank machine boards, moves, and exits one rider")
    func machineBoardsMovesAndExits() throws {
        var machine = try ElevatorBank.makeMachine()
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.floor) == .one)
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.door) == .closed)
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.rider) == ElevatorBank.Rider.none)
        #expect(machine.state.riders[.alice]?.value(for: ElevatorBank.RiderSchema.phase) == .waiting)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.door) == .open)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.door) == .closed)
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.rider) == .alice)
        #expect(machine.state.riders[.alice]?.value(for: ElevatorBank.RiderSchema.phase) == .onboard)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.floor) == .two)
        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.floor) == .three)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.door) == .open)
        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.rider) == ElevatorBank.Rider.none)
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.door) == .closed)
        #expect(machine.state.riders[.alice]?.value(for: ElevatorBank.RiderSchema.phase) == .arrived)
    }
}
