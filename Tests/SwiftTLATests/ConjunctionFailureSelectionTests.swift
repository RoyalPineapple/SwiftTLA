import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Conjunction failure selection")
struct ConjunctionFailureSelectionTests {
    @Test("Generated outputs evaluate writes before merge and select failures in order", arguments: [false, true])
    func emittedFailureOrder(overlappingTarget: Bool) throws {
        let specification = TLASpec(name: "FallibleConjunction", variables: [
            .init(name: "divisor", initial: .int(1)),
            .init(name: "left", initial: .int(0)),
            .init(name: "right", initial: .int(0)),
        ], actions: [.init(name: "step", body: .and(
            .assign(.named(overlappingTarget ? "right" : "left"), .divide(.int(1), .variable("divisor"))),
            .assign(.named("right"), .add(.int(.max), .int(1)))))], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let action = try #require(program.behavior.actions.first)
        guard case .and(_, _) = action.body else {
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

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "FallibleConjunction", program: program))
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let writes = try emitter.actionFunctions(action.body).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let fallible = try #require(writes.last { $0.value.contains("try ") })
        let merge = "if let merged = updates.merging(_Updates(\(fallible.slot): \(fallible.value))) { try emit(merged) }"
        let skippedFailure = visitor.description.replacingOccurrences(of: merge,
            with: "if updates.\(fallible.slot) != nil { return }\n\(merge)")
        #expect(skippedFailure != visitor.description)
        let changed = try #require(Parser.parse(source: skippedFailure)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(changed, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("A pending write suppressed a fallible assignment before evaluation")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.write.\(fallible.id)")
        }
    }

    @Test("Generated TLA+ selects guard and body failures in evaluation order", arguments: [false, true])
    func guardedFailureSelection(fallibleGuard: Bool) throws {
        let condition: StateExpr = fallibleGuard
            ? .equal(.add(.variable("value"), .int(1)), .int(0))
            : .equal(.variable("value"), .int(0))
        let specification = TLASpec(name: "GuardedFailure", variables: [
            .init(name: "value", initial: .int(0)),
        ], actions: [.init(name: "step", body: .and(
            .guard_(condition),
            .assign(.named("value"), .add(.int(.max), .int(1)))))], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        guard case .and(.guard_(_), _) = try #require(program.behavior.actions.first).body else {
            Issue.record("The compiled action did not retain the guarded conjunction")
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
        let bodySite = fallibleGuard ? "0_1" : "0"
        for (prefix, wrongValue) in [
            ("__SwiftTLAOverflowFailure0", "TRUE"),
            ("__SwiftTLAOverflowOperands\(bodySite)", "<<0, 0>>"),
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
