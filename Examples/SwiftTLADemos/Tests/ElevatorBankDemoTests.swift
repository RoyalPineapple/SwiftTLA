import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ElevatorBankDemoTests {
    @Test("elevator bank keeps every car, door, and rider transition in the generated model")
    func formalMachineBoardsMovesAndExits() throws {
        let builderSpec = ElevatorBank.spec
        let builderTree = ParsedSpecModel(
            variables: builderSpec.variables.map { ($0.name, $0.initial, $0.initialSet) },
            actions: builderSpec.actions.map { ($0.name, $0.body, $0.bindings) },
            invariants: builderSpec.invariants.map { ($0.name, $0.body) },
            temporal: builderSpec.temporalProperties.map { ($0.name, $0.expr) },
            fairness: builderSpec.fairness
        )
        #expect(
            _tlaAlphaEquivalent(builderTree, ElevatorBank._parserTree),
            Comment(rawValue: _tlaFidelityDiagnostic(ElevatorBank._parserTree, builderTree))
        )
        try ElevatorBank.verifySpec()
        try ElevatorBank.verifyTransitions()
        try ElevatorBank.verifyInvariants()
        #expect(try ElevatorBank.transitionMatrix().isEmpty == false)

        var machine = ElevatorBank()
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.floor] == .one)
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.door] == .closed)
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.rider] == .none)
        #expect(machine.state.riders[.alice][ElevatorBank.RiderSchema.phase] == .waiting)

        _ = try machine.apply(.operate(process: .carA))
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.door] == .open)

        _ = try machine.apply(.operate(process: .carA))
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.door] == .closed)
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.rider] == .alice)
        #expect(machine.state.riders[.alice][ElevatorBank.RiderSchema.phase] == .onboard)

        _ = try machine.apply(.operate(process: .carA))
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.floor] == .two)
        _ = try machine.apply(.operate(process: .carA))
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.floor] == .three)

        _ = try machine.apply(.operate(process: .carA))
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.door] == .open)
        _ = try machine.apply(.operate(process: .carA))
        #expect(machine.state.cars[.carA][ElevatorBank.CarSchema.rider] == .none)
        #expect(machine.state.riders[.alice][ElevatorBank.RiderSchema.phase] == .arrived)
    }
}
