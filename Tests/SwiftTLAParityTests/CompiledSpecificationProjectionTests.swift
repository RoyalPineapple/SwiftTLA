import Testing
@testable import SwiftTLA
@testable import UpstreamParity

private enum CompiledProjectionLabel: String, CaseIterable {
    case advance
}

@Suite("Compiled specification projections")
struct CompiledSpecificationProjectionTests {
    @Test("Every downstream consumer retains one compiled specification")
    func downstreamConsumersRetainOneCompilation() throws {
        let specification = TLASpec("CompiledProjection") {
            Algorithm("CompiledProjection", scoped: { scope in
                let counter = scope.sharedVar("counter", initial: 0)
                Do(CompiledProjectionLabel.advance) {
                    Assign(counter, to: counter + 1)
                    Stop()
                }
            })
        }
        let compilation = try specification.compile()

        let tla = compilation.renderedTLAModuleBundle()
        let plusCal = try compilation.renderedPlusCalBundle()
        let exploration = try ModelChecker(
            compilation: compilation,
            configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)
        ).explore()
        let matchingCase = try FiniteGraphCase(
            id: "compiled-projection",
            exploration: exploration.configuration,
            moduleSHA256: String(repeating: "a", count: 64),
            cfgSHA256: String(repeating: "b", count: 64),
            arguments: [],
            environment: [:],
            pin: try testReferencePin()
        )
        let completedRun = try SwiftGraphExporter().export(exploration, for: matchingCase)

        #expect(tla.root.tla.contains("MODULE CompiledProjection"))
        #expect(plusCal.root.tla.contains("--algorithm CompiledProjection"))
        if case let .compiled(identity, _, _) = tla.provenance {
            #expect(identity == compilation.identity)
        } else {
            Issue.record("TLA bundle must retain compiled provenance.")
        }
        if case let .compiled(identity, _, _) = plusCal.provenance {
            #expect(identity == compilation.identity)
        } else {
            Issue.record("PlusCal bundle must retain compiled provenance.")
        }
        #expect(exploration.compilationIdentity == compilation.identity)
        #expect(exploration.graph.states.count == 2)
        #expect(completedRun.graph.variableNames.contains("counter"))
        #expect(completedRun.graph.initialStateKeys.count == 1)
        #expect(completedRun.graph.edgeOccurrences.count == 2)
        #expect(completedRun.graph.edgeOccurrences.values.sorted() == [1, 1])
        #expect(completedRun.observableActions == ["Terminating", "advance"])
        #expect(completedRun.outcome == .exhaustiveSuccess)
    }
}
