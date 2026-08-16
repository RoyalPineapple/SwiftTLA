@testable import AlgorithmConformance
import Testing

struct K3SimultaneousAssignmentWitnessTests {
    @Test("K3 simultaneous assignments read the old state and commit together")
    func generatedSimultaneousAssignmentSurface() throws {
        K3SimultaneousAssignmentWitness._checkParserTree()

        var model = K3SimultaneousAssignmentWitness()
        let swap = try model.apply(.swap)

        #expect(swap.before.left == 1)
        #expect(swap.before.right == 2)
        #expect(swap.after.left == 2)
        #expect(swap.after.right == 1)
        #expect(model.state == swap.after)
    }

    @Test("K3 fixture exposes one authored PlusCal simultaneous assignment module")
    func exposesSimultaneousAssignmentOracleFixture() throws {
        let fixture = AlgorithmConformanceRegistry.simultaneousAssignment
        let source = try fixture.plusCalModule()

        #expect(source.contains("left := right || right := left;"))
        #expect(fixture.configuration.contains("SPECIFICATION Spec"))
    }
}
