import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ConfiguredPlusCalExportTests {
    @Test("generated PlusCal shares symbolic parameters and exact scenario configuration with TLA")
    func preservesConfiguration() throws {
        var sources = Set<String>()
        for scenario in try ConfiguredCounter.validationScenarios() {
            let rendered = try scenario.render()
            let authored = try rendered.plusCalBundle()
            #expect(authored.cfg == rendered.tlaBundle.cfg)
            #expect(authored.provenance == rendered.tlaBundle.provenance)
            #expect(authored.tla.contains("CONSTANTS limit, stopAtLimit"))
            #expect(authored.tla.contains("ASSUME limit \\in 1..100"))
            #expect(authored.tla.contains("--algorithm Counter"))
            #expect(authored.tla.contains("value < limit"))
            sources.insert(authored.tla)
        }
        #expect(sources.count == 1)
    }

    @Test("authored process-local expressions retain complete types through resolution")
    func retainsResolvedTypes() throws {
        let compilation = try RecurringPopulation.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let authored = try #require(program.authoredAlgorithm)
        var pending: [CompiledExpression] = []
        _ = authored.map { pending.append($0); return $0 }
        #expect(!pending.isEmpty)
        while let expression = pending.popLast() {
            #expect(expression.resultType.resolved)
            #expect(expression.computationType.resolved)
            if case .operatorApplication = expression.operation {
                Issue.record("Authored expressions must contain resolved calls, not unresolved operators")
            }
            pending.append(contentsOf: expression.children)
        }
        let process = try #require(authored.processes.first)
        #expect(program.bindingTypes[process.binder] == .int)
        let local = try #require(process.locals.first)
        #expect(program.variableTypes[local.variable] == .dictionary(.int, .bool))
        guard case .expression(let initializer) = local.initialization else {
            Issue.record("Expected a typed local initializer")
            return
        }
        #expect(initializer.resultType == .bool)
    }
}
