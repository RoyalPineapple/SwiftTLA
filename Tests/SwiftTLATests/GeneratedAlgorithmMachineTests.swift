@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedAlgorithmMachineTests {
    @Test("generated actions retain collision-safe Swift cases")
    func sanitizesGeneratedActions() {
        let dotted = SanitizedActionModel.Action.procedure_work_enter
        let underscored = SanitizedActionModel.Action.procedure_work_enter_2
        let dashed = SanitizedActionModel.Action.step_2
        #expect((dotted == underscored) == false)
        #expect((underscored == dashed) == false)
        #expect((dashed == dotted) == false)
    }

    @Test("generated actions accept a case named toInvocation")
    func permitsCurrentActionNames() {
        #expect(InvocationNamedActionModel.Action.toInvocation == .toInvocation)
    }

    @Test("a bounded Algorithm generates the ordinary typed state machine")
    func generatedAlgorithmUsesTheSharedLowering() throws {
        var machine = try GeneratedAlgorithmCounter.makeMachine()
        #expect(machine.state.count == 0)
        let action = GeneratedAlgorithmCounter.Action.increment(process: .left)
        let transition = try machine.send(action)
        #expect(transition.before.count == 0)
        #expect(transition.after.count == 1)
        #expect(machine.state.count == 1)
    }

    @Test("a generated machine accepts one declared initial state")
    func generatedMachineAcceptsDeclaredInitialState() throws {
        var machine = try SeededCounterMachine.makeMachine(.init(value: 2))

        #expect(machine.state.value == 2)
        #expect(try machine.send(.advance).after.value == 0)
    }

    @Test("a generated machine rejects an initial state outside Init")
    func generatedMachineRejectsUndeclaredInitialState() {
        do {
            _ = try SeededCounterMachine.makeMachine(.init(value: 3))
            Issue.record("Expected an invalid initial state error")
        } catch GeneratedMachineError.invalidInitialState {
        } catch {
            Issue.record("Expected an invalid initial state error, got \(error)")
        }
    }

    @Test("a generated machine does not select an arbitrary initial state")
    func generatedMachineRequiresAnInitialStateWhenInitIsPlural() {
        do {
            _ = try SeededCounterMachine.makeMachine()
            Issue.record("Expected an ambiguous initial state error")
        } catch GeneratedMachineError.ambiguousInitialState {
        } catch {
            Issue.record("Expected an ambiguous initial state error, got \(error)")
        }
    }
}
