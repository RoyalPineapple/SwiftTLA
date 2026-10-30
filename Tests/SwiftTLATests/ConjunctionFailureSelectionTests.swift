import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Conjunction failure selection")
struct ConjunctionFailureSelectionTests {
    @Test("Generated TLA+ reports a right failure only after an enabled left action")
    func emittedFailureOrder() throws {
        let specification = TLASpec(name: "FallibleConjunction", variables: [
            .init(name: "divisor", initial: .int(1)),
            .init(name: "left", initial: .int(0)),
            .init(name: "right", initial: .int(0)),
        ], actions: [.init(name: "step", body: .and(
            .assign(.named("left"), .divide(.int(1), .variable("divisor"))),
            .assign(.named("right"), .add(.int(.max), .int(1)))))], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        guard case .and(_, _) = try #require(program.behavior.actions.first).body else {
            Issue.record("The compiled action lost its conjunction")
            return
        }
        let output = try program.renderModule()
        let renderer = CompiledTLARenderer(moduleName: program.moduleName,
            reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions,
            enums: program.enums, parameterDomains: program.behavior.parameterDomains)
        func verify(_ module: String, _ declarations: [String]) throws {
            try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
                module: module, failureDeclarations: declarations,
                evaluationInvariant: "__SwiftTLAEvaluationOK",
                configuration: output.configuration, renderer: renderer)
        }
        try verify(output.renderedModuleSource, output.evaluationFailureDeclarations)
        for (prefix, wrongValue) in [
            ("__SwiftTLAOverflowFailure0_1", "TRUE"),
            ("__SwiftTLAOverflowOperands0_1", "<<0, 0>>"),
            ("__SwiftTLAAnyEvaluationFailure0", "TRUE"),
        ] {
            let original = try #require(output.evaluationFailureDeclarations.first {
                $0.hasPrefix("\(prefix) == ")
            })
            let changed = "\(prefix) == \(wrongValue)"
            #expect(throws: CompilationDiagnostic.self) {
                try verify(output.renderedModuleSource.replacingOccurrences(of: original, with: changed),
                    output.evaluationFailureDeclarations.map { $0 == original ? changed : $0 })
            }
        }
    }
}
