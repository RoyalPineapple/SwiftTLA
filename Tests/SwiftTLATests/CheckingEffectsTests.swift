import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct CheckingEffectsTests {
    @Test("Writes survive rejected candidates and later candidates see them")
    func preservesImmediateWrites() throws {
        let machine = try OrderedCheckingEffects.makeMachine()
        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        try context.advanceBreadthFirstLevel()
        let successors = try machine.successors(checking: &context)
        #expect(successors.count == 1)
        #expect(successors.first?.machine.state.value == 12)
        #expect(context.registers.visits == 12)
        #expect(context.registers.observedLevel == 1)
        #expect(machine.state.value == 0)
        #expect(try machine.initialCheckingRegisters().visits == 0)
        try context.advanceBreadthFirstLevel()
        #expect(try machine.successors(checking: &context).first?.machine.state.value == 1212)
        #expect(context.registers.observedLevel == 2)
    }

    @Test("Context-free execution cannot silently reset checking registers")
    func requiresRunContext() throws {
        let machine = try OrderedCheckingEffects.makeMachine()
        #expect(throws: NativeMachineEvaluationError.checkingContextRequired) { try machine.successors() }
    }

    @Test("The same checked register identities render as TLC get and set operations")
    func exportsRegisterOperations() throws {
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: OrderedCheckingEffects.spec.compile()))
        let module = try program.renderModule().renderedModuleSource
        #expect(module.contains("TLCGet(0)"))
        #expect(module.contains("TLCSet(0,"))
        #expect(module.contains("TLCGet(\"level\")"))
        #expect(program.layout.variables.map { $0.declaration.name } == ["value"])
    }
}
