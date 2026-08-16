@testable import AlgorithmConformance
import SwiftTLA
import Testing

struct K6BoulangerMCWitnessTests {
    @Test("K6 Boulanger witness preserves the MCBoulanger initial flags and ncs back edge")
    func preservesSourceFidelity() throws {
        let fidelityEvidence = parserFidelityEvidence()
        #expect(fidelityEvidence == nil, Comment(rawValue: fidelityEvidence?.description ?? "No parser/builder difference."))

        let source = try AlgorithmConformanceRegistry.k6BoulangerMC.plusCalModule()
        #expect(source.contains("flag = [i \\in (1..3) |-> FALSE]"))
        #expect(source.contains("num[self] := 0;\n      goto ncs;"))
        #expect(K6BoulangerMCWitness.spec.algorithmFidelityTokens.count == 1)
    }

    private func parserFidelityEvidence() -> TLAParserFidelityDiagnostic? {
        let builtSpec = K6BoulangerMCWitness.spec
        let built = ParsedSpecModel(
            variables: builtSpec.variables.map { ($0.name, $0.initial, $0.initialSet) },
            actions: builtSpec.actions.map { ($0.name, $0.body, $0.bindings) },
            invariants: builtSpec.invariants.map { ($0.name, $0.body) },
            temporal: builtSpec.temporalProperties.map { ($0.name, $0.expr) },
            fairness: builtSpec.fairness,
            constraint: builtSpec.constraint,
            imports: builtSpec.imports.map(\.name),
            importConfigurations: builtSpec.importConfigurations,
            moduleInstances: builtSpec.moduleInstances,
            formalParameters: builtSpec.formalParameters,
            formalOperatorDefinitions: builtSpec.formalOperatorDefinitions
        )
        return _tlaAlgorithmFidelityEvidence(
            K6BoulangerMCWitness._parserAlgorithmTokens,
            builtSpec.algorithmFidelityTokens
        ) ?? _tlaFidelityEvidence(K6BoulangerMCWitness._parserTree, built)
    }

    @Test("K6 fixture carries the bounded constraint that its source actually uses")
    func retainsBoundedConfiguration() {
        let fixture = AlgorithmConformanceRegistry.k6BoulangerMC

        #expect(!fixture.configuration.contains("NatOverride"))
        #expect(fixture.configuration.contains("CONSTRAINT StateConstraint"))
    }
}
