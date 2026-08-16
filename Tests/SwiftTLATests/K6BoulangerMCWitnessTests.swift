@testable import AlgorithmConformance
import Testing

struct K6BoulangerMCWitnessTests {
    @Test("K6 Boulanger witness preserves the MCBoulanger initial flags and ncs back edge")
    func preservesSourceFidelity() throws {
        K6BoulangerMCWitness._checkParserTree()

        let source = try AlgorithmConformanceRegistry.k6BoulangerMC.plusCalModule()
        #expect(source.contains("flag = [i \\in (1..3) |-> FALSE]"))
        #expect(source.contains("num[self] := 0;\n      goto ncs;"))
        #expect(K6BoulangerMCWitness.spec.algorithmFidelityTokens.count == 1)
    }

    @Test("K6 fixture retains its published bounded configuration")
    func retainsMCBoulangerConfiguration() {
        let fixture = AlgorithmConformanceRegistry.k6BoulangerMC

        #expect(fixture.configuration.contains("CONSTANT N = 3"))
        #expect(fixture.configuration.contains("CONSTANT MaxNat = 3"))
        #expect(fixture.configuration.contains("CONSTANT Nat <- NatOverride"))
        #expect(fixture.configuration.contains("CONSTRAINT StateConstraint"))
    }
}
