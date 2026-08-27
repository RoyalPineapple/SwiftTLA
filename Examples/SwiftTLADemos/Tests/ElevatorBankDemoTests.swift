import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ElevatorBankDemoTests {
    @Test("elevator bank keeps every car, door, and rider transition in the generated model")
    func formalMachineBoardsMovesAndExits() throws {
        let builderSpec = ElevatorBank.spec
        #expect(try builderSpec.compile().renderedTLAModuleBundle().tla == try ElevatorBank.spec.compile().renderedTLAModuleBundle().tla)

        var machine = try ElevatorBank.makeMachine()
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.floor) == .one)
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.door) == .closed)
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.rider) == .none)
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
        #expect(machine.state.cars[.carA]?.value(for: ElevatorBank.CarSchema.rider) == .none)
        #expect(machine.state.riders[.alice]?.value(for: ElevatorBank.RiderSchema.phase) == .arrived)
    }
}
