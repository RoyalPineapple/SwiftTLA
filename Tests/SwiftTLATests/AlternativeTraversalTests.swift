import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import Testing

@Suite("Alternative traversal")
struct AlternativeTraversalTests {
    @Test("Boolean conditions survive normalization, compilation, and TLA+ emission")
    func scalarConditionsSurviveNormalizationAndRendering() throws {
        let variables = [
            NamedVar(name: "enabled", initial: .bool(false)),
            NamedVar(name: "x", initial: .int(0)),
        ]
        let roots: Set<String> = ["enabled", "x"]
        let conditional = ActionExpr.ifElse(.variable("enabled"),
            .assign(.named("x"), .int(1)), .assign(.named("x"), .int(2)))
        let guarded = ActionExpr.and(.guard_(.variable("enabled")), .assign(.named("x"), .int(3)))
        let specification = TLASpec(name: "ConditionalNormalization", variables: variables,
            actions: [.init(name: "choose", body: conditional), .init(name: "gated", body: guarded)],
            invariants: [])
        let compilation = try specification.compile()
        try StraightLineAssignmentCheck.verifyNormalization(conditional,
            normalized: ActionNormalization.complete(conditional, variables: variables),
            stateRoots: roots, at: "actions.choose.normalization")
        try StraightLineAssignmentCheck.verifyNormalization(guarded,
            normalized: ActionNormalization.complete(guarded, variables: variables),
            stateRoots: roots, at: "actions.gated.normalization")

        let reversed = ActionExpr.ifElse(.variable("enabled"),
            .assign(.named("x"), .int(2)), .assign(.named("x"), .int(1)))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyNormalization(conditional,
                normalized: ActionNormalization.complete(reversed, variables: variables),
                stateRoots: roots, at: "actions.choose.normalization")
        }
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyNormalization(guarded,
                normalized: ActionNormalization.complete(.assign(.named("x"), .int(3)),
                    variables: variables), stateRoots: roots, at: "actions.gated.normalization")
        }

        let inputs = try SourceTypeResolver().resolve(in: compilation)
        let program = try CompiledProgram(inputs: inputs)
        let sourceActions = try specification.loweredSourceModel().actions
        let untypedActions = compilation.semantics.behavior.actions
        let resolvedActions = program.behavior.actions
        let enabledID = try #require(compilation.layout.variables.first {
            $0.declaration.name == "enabled"
        }?.id)
        try #require(sourceActions.count == 2 && untypedActions.count == 2 && resolvedActions.count == 2)
        for index in 0..<2 {
            let source = sourceActions[index]
            let untyped = untypedActions[index]
            let resolved = resolvedActions[index]
            try StraightLineAssignmentCheck.verifyCompiled(source, bindings: untyped.bindings,
                body: untyped.body, layout: compilation.layout)
            try StraightLineAssignmentCheck.verifyResolved(untyped, resolved: resolved,
                variableTypes: inputs.variableTypes, resolvedVariableTypes: program.variableTypes,
                resolvedBindingTypes: program.bindingTypes)
            var changed = 0
            let wrong = untyped.body.map { expression in
                guard expression.operation == .stateVariable(enabledID) else { return expression }
                changed += 1
                return CompiledExpression(operation: .value(.boolean(false)),
                    resultType: expression.resultType, children: [])
            }
            #expect(changed == 1)
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineAssignmentCheck.verifyCompiled(source, bindings: untyped.bindings,
                    body: wrong, layout: compilation.layout)
            }
            let wrongResolved = resolved.body.map { expression in
                guard expression.operation == .stateVariable(enabledID) else { return expression }
                return CompiledExpression(operation: .value(.boolean(false)),
                    resultType: expression.resultType, children: [])
            }
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineAssignmentCheck.verifyResolved(untyped,
                    resolved: .init(id: resolved.id, bindings: resolved.bindings, body: wrongResolved),
                    variableTypes: inputs.variableTypes, resolvedVariableTypes: program.variableTypes,
                    resolvedBindingTypes: program.bindingTypes)
            }
        }

        let module = try compilation.render().tlaBundle.tla
        let actions = compilation.semantics.behavior.actions
        let chooseLine = try #require(module.split(separator: "\n").first { $0.hasPrefix("choose == ") })
        let gatedLine = try #require(module.split(separator: "\n").first { $0.hasPrefix("gated == ") })
        let chooseBody = String(chooseLine.dropFirst("choose == ".count))
        let gatedBody = String(gatedLine.dropFirst("gated == ".count))
        try StraightLineRenderedActionCheck.verify(actions[0].body, rendered: chooseBody,
            layout: compilation.layout, binders: compilation.bindings.binders)
        try StraightLineRenderedActionCheck.verify(actions[1].body, rendered: gatedBody,
            layout: compilation.layout, binders: compilation.bindings.binders)

        let wrongCondition = chooseBody.replacingOccurrences(of: "IF enabled THEN", with: "IF FALSE THEN")
        #expect(wrongCondition != chooseBody)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(actions[0].body, rendered: wrongCondition,
                layout: compilation.layout, binders: compilation.bindings.binders)
        }
        let droppedGuard = gatedBody.replacingOccurrences(of: "(enabled) = TRUE", with: "TRUE")
        #expect(droppedGuard != gatedBody)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(actions[1].body, rendered: droppedGuard,
                layout: compilation.layout, binders: compilation.bindings.binders)
        }
    }

    @Test("Normalization retains every scalar branch and completes its state frame")
    func scalarNormalizationPreservesCompleteSuccessors() throws {
        let variables = ["x", "y", "z"].map { NamedVar(name: $0, initial: .int(0)) }
        let source = ActionExpr.and(
            .or(.assign(.named("x"), .int(1)), .assign(.named("x"), .int(2))),
            .assign(.named("y"), .int(3)))
        let normalized = ActionNormalization.complete(source, variables: variables)
        try StraightLineAssignmentCheck.verifyNormalization(source, normalized: normalized,
            stateRoots: ["x", "y", "z"], at: "actions.pick.normalization")
        _ = try TLASpec(name: "ScalarNormalization", variables: variables,
            actions: [.init(name: "pick", body: source)], invariants: []).compile()

        let bound = ActionExpr.define("chosen", .int(2),
            .or(.assign(.named("x"), .variable("chosen")), .assign(.named("x"), .int(1))))
        try StraightLineAssignmentCheck.verifyNormalization(bound,
            normalized: ActionNormalization.complete(bound, variables: variables),
            stateRoots: ["x", "y", "z"], at: "actions.bound.normalization")

        let dropped = ActionNormalization.complete(
            .and(.assign(.named("x"), .int(1)), .assign(.named("y"), .int(3))),
            variables: variables)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyNormalization(source, normalized: dropped,
                stateRoots: ["x", "y", "z"], at: "actions.pick.normalization")
        }
        let unframed = ActionExpr.or(
            .and(.assign(.named("x"), .int(1)), .and(.assign(.named("y"), .int(3)), .unchanged(.named("z")))),
            .and(.assign(.named("x"), .int(2)), .assign(.named("y"), .int(3))))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyNormalization(source, normalized: unframed,
                stateRoots: ["x", "y", "z"], at: "actions.pick.normalization")
        }
    }

    @Test("Fallible action alternatives retain source order through normalization")
    func fallibleBranchwiseNormalization() throws {
        let variables = ["divisor", "x", "y"].map { NamedVar(name: $0, initial: .int(0)) }
        let first = ActionExpr.assign(.named("x"), .divide(.int(1), .variable("divisor")))
        let second = ActionExpr.assign(.named("x"), .modulo(.int(1), .variable("divisor")))
        let continuation = ActionExpr.assign(.named("y"), .add(.variable("x"), .int(1)))
        let source = ActionExpr.and(.or(first, second), continuation)
        let normalized = ActionNormalization.complete(source, variables: variables)
        try StraightLineAssignmentCheck.verifyNormalization(source, normalized: normalized,
            stateRoots: ["divisor", "x", "y"], at: "actions.pick.normalization")
        let specification = TLASpec(name: "FallibleBranchwiseNormalization", variables: variables,
            actions: [.init(name: "pick", body: source)], invariants: [])
        let compilation = try specification.compile()
        let sourceAction = try #require(specification.loweredSourceModel().actions.first)
        let action = try #require(compilation.semantics.behavior.actions.first)
        let inputs = try SourceTypeResolver().resolve(in: compilation)
        let program = try CompiledProgram(inputs: inputs)
        let resolved = try #require(program.behavior.actions.first)
        for operation: CompiledOperation in [.divide, .modulo] {
            var changed = 0
            let wrong = action.body.map { expression in
                guard expression.operation == operation else { return expression }
                changed += 1
                return CompiledExpression(operation: .add, resultType: expression.resultType,
                    children: expression.children)
            }
            #expect(changed == 1)
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
                    bindings: action.bindings, body: wrong, layout: compilation.layout)
            }
            let wrongResolved = resolved.body.map { expression in
                guard expression.operation == operation else { return expression }
                return CompiledExpression(operation: .add, resultType: expression.resultType,
                    children: expression.children)
            }
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineAssignmentCheck.verifyResolved(action,
                    resolved: .init(id: resolved.id, bindings: resolved.bindings, body: wrongResolved),
                    variableTypes: inputs.variableTypes, resolvedVariableTypes: program.variableTypes,
                    resolvedBindingTypes: program.bindingTypes)
            }
        }

        let reordered = ActionNormalization.complete(.and(.or(second, first), continuation),
            variables: variables)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyNormalization(source, normalized: reordered,
                stateRoots: ["divisor", "x", "y"], at: "actions.pick.normalization")
        }
    }

    @Test("Fallible conditional continuations retain both branches during normalization")
    func fallibleConditionalContinuationNormalization() throws {
        let variables = ["divisor", "x", "y"].map { NamedVar(name: $0, initial: .int(0)) }
        let condition = StateExpr.equal(.divide(.int(1), .variable("divisor")), .int(0))
        let choose = ActionExpr.ifElse(condition,
            .assign(.named("x"), .int(1)), .assign(.named("x"), .int(2)))
        let continuation = ActionExpr.assign(.named("y"), .int(3))
        let source = ActionExpr.and(choose, continuation)
        let normalized = ActionNormalization.complete(source, variables: variables)
        try StraightLineAssignmentCheck.verifyNormalization(source, normalized: normalized,
            stateRoots: ["divisor", "x", "y"], at: "actions.pick.normalization")

        let missingElseContinuation = ActionNormalization.complete(.ifElse(condition,
            .and(.assign(.named("x"), .int(1)), continuation),
            .assign(.named("x"), .int(2))), variables: variables)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyNormalization(source,
                normalized: missingElseContinuation,
                stateRoots: ["divisor", "x", "y"], at: "actions.pick.normalization")
        }

        let duplicatedCondition = ActionNormalization.complete(.or(
            .and(.guard_(condition), .and(.assign(.named("x"), .int(1)), continuation)),
            .and(.guard_(.not(condition)), .and(.assign(.named("x"), .int(2)), continuation))),
            variables: variables)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyNormalization(source,
                normalized: duplicatedCondition,
                stateRoots: ["divisor", "x", "y"], at: "actions.pick.normalization")
        }
    }

    @Test("Scalar alternatives retain both branches through compilation and TLA+ emission")
    func renderedAlternativesKeepBothBranches() throws {
        let specification = TLASpec(name: "ScalarAlternatives", variables: [
            .init(name: "value", initial: .int(0))
        ], actions: [
            .init(name: "pick", body: .or(
                .assign(.named("value"), .int(1)),
                .assign(.named("value"), .int(2))))
        ], invariants: [])
        let compilation = try specification.compile()
        let action = try #require(compilation.semantics.behavior.actions.first)
        let sourceAction = try #require(specification.loweredSourceModel().actions.first)
        let inputs = try SourceTypeResolver().resolve(in: compilation)
        let program = try CompiledProgram(inputs: inputs)
        let resolved = try #require(program.behavior.actions.first)
        guard case .or(let left, let right) = action.body else {
            Issue.record("The compiled action lost its alternatives")
            return
        }
        let lostAlternative = CompiledActionExpr.and(left, right)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyCompiled(sourceAction, bindings: action.bindings,
                body: lostAlternative, layout: compilation.layout)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolved(action,
                resolved: .init(id: resolved.id, bindings: resolved.bindings, body: lostAlternative),
                variableTypes: inputs.variableTypes, resolvedVariableTypes: program.variableTypes,
                resolvedBindingTypes: program.bindingTypes)
        }
        let module = try compilation.render().tlaBundle.tla
        let declaration = try #require(module.split(separator: "\n").first { $0.hasPrefix("pick == ") })
        let body = String(declaration.dropFirst("pick == ".count))
        try StraightLineRenderedActionCheck.verify(action.body, rendered: body,
            layout: compilation.layout, binders: compilation.bindings.binders)

        let conjunction = body.replacingOccurrences(of: " \\/ ", with: " /\\ ")
        #expect(conjunction != body)
        do {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: conjunction,
                layout: compilation.layout, binders: compilation.bindings.binders)
            Issue.record("A rendered conjunction discarded an alternative successor")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.action.scalarAssignments")
        }
    }

    @Test("Generated TLA+ guards a later alternative failure after an earlier one")
    func renderedAlternativeFailureOrder() throws {
        let specification = TLASpec(name: "FallibleAlternatives", variables: [
            .init(name: "divisor", initial: .int(0)),
            .init(name: "value", initial: .int(0)),
        ], actions: [.init(name: "pick", body: .or(
            .assign(.named("value"), .divide(.int(1), .variable("divisor"))),
            .assign(.named("value"), .add(.int(.max), .int(1)))))], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let output = try program.renderModule()
        let renderer = CompiledTLARenderer(moduleName: program.moduleName,
            reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions,
            enums: program.enums, parameterDomains: program.behavior.parameterDomains)
        try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
            module: output.renderedModuleSource,
            failureDeclarations: output.evaluationFailureDeclarations,
            evaluationInvariant: "__SwiftTLAEvaluationOK",
            configuration: output.configuration, renderer: renderer)
        let original = try #require(output.evaluationFailureDeclarations.first {
            $0.hasPrefix("__SwiftTLAAnyEvaluationFailure0 == ")
        })
        let changed = "__SwiftTLAAnyEvaluationFailure0 == TRUE"
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
                module: output.renderedModuleSource.replacingOccurrences(of: original, with: changed),
                failureDeclarations: output.evaluationFailureDeclarations.map { $0 == original ? changed : $0 },
                evaluationInvariant: "__SwiftTLAEvaluationOK",
                configuration: output.configuration, renderer: renderer)
        }
        for (prefix, wrongValue) in [
            ("__SwiftTLADivisionByZeroDivisor0", "2"),
            ("__SwiftTLAOverflowOperands0_1", "<<0, 0>>"),
            ("__SwiftTLAOverflowOperation0_1", "\"subtraction\""),
        ] {
            let original = try #require(output.evaluationFailureDeclarations.first {
                $0.hasPrefix("\(prefix) == ")
            })
            let changed = "\(prefix) == \(wrongValue)"
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
                    module: output.renderedModuleSource.replacingOccurrences(of: original, with: changed),
                    failureDeclarations: output.evaluationFailureDeclarations.map { $0 == original ? changed : $0 },
                    evaluationInvariant: "__SwiftTLAEvaluationOK",
                    configuration: output.configuration, renderer: renderer)
            }
        }
    }

    @Test("Generated TLA+ retains ordered addition failure payloads across alternatives")
    func renderedAlternativeAdditionPayloads() throws {
        let specification = TLASpec(name: "AdditionAlternatives", variables: [
            .init(name: "value", initial: .int(0))
        ], actions: [.init(name: "pick", body: .or(
            .assign(.named("value"), .add(.variable("value"), .int(1))),
            .assign(.named("value"), .add(.variable("value"), .int(2)))))], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
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
            ("__SwiftTLAOverflowOperands0", "<<0, 0>>"),
            ("__SwiftTLAOverflowOperation0_1", "\"subtraction\""),
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

    @Test("Nested alternatives retain source order after normalization")
    func nestedAlternativeOrder() {
        let leaves = (1...4).map { ActionExpr.assign(.named("value"), .int($0)) }
        let leftNested = ActionExpr.or(.or(.or(leaves[0], leaves[1]), leaves[2]), leaves[3])
        let rightNested = ActionExpr.or(leaves[0], .or(leaves[1], .or(leaves[2], leaves[3])))
        for source in [leftNested, rightNested] {
            #expect(ActionNormalization.branches(of: source) == leaves)
        }
    }

    @Test("Compiled actions require branchwise continuations before emission")
    func branchwiseContinuation() throws {
        let variable = VariableID(ordinal: 0)
        let undistributed = CompiledActionExpr.and(
            .or(.unchanged(variable), .unchanged(variable)),
            .unchanged(variable)
        )
        do {
            try undistributed.verifyBranchwiseContinuation(at: "actions.pick.body")
            Issue.record("An undistributed compiled action must not reach either emitter")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidFormalDeclaration)
            #expect(diagnostic.stage == .lowering)
        }
        let source = ActionExpr.and(
            .or(.assign(.named("value"), .int(1)), .assign(.named("value"), .int(2))),
            .guard_(.bool(true))
        )
        let compilation = try canonicalTestSpec(
            variables: [("value", .value(.int(0)))], actions: [("pick", source, [])]
        ).compile()
        let lowered = try #require(compilation.semantics.behavior.actions.first)
        try lowered.body.verifyBranchwiseContinuation(at: "actions.pick.body")
    }

    @Test("Successful updates survive a failing alternative")
    func mixedOutcomes() {
        var emitted: [Int] = []
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.visitAlternatives([0, 1], emit: { emitted.append($0) }) { alternative, emit in
                try emit(alternative)
                try emit(alternative == 0 ? 0 : 2)
                if alternative == 0 { throw NativeMachineEvaluationError.divisionByZero }
            }
        }
        #expect(emitted == [0, 0, 1, 2])
    }

    @Test("The Swift alternative kernel matches the proved ordered traversal")
    func kernelMatchesProofRule() throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let source = try String(contentsOf: directory.appendingPathComponent(
            "../../Sources/SwiftTLA/NativeMachineOperations.swift").standardizedFileURL, encoding: .utf8)
        let parsed = Parser.parse(source: source)
        let owner = try #require(parsed.statements.compactMap {
            $0.item.as(EnumDeclSyntax.self)
        }.first { $0.name.text == "_NativeMachineOperations" })
        let actual = try #require(owner.memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }.first { $0.name.text == "visitAlternatives" })
        let witness = try String(contentsOf: directory.appendingPathComponent(
            "../../Verification/Semantics/AlternativeTraversalSwiftKernel.txt").standardizedFileURL,
            encoding: .utf8)
        let expected = try #require(Parser.parse(source: witness).statements.first?
            .item.as(FunctionDeclSyntax.self))
        let expectedTokens = expected.tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actual.tokens(viewMode: .sourceAccurate).map(\.text) == expectedTokens)

        let reversed = actual.description.replacingOccurrences(
            of: "for update in updates { try emit(update) }",
            with: "for update in updates.reversed() { try emit(update) }")
        #expect(reversed != actual.description)
        let mutant = try #require(Parser.parse(source: reversed).statements.first?
            .item.as(FunctionDeclSyntax.self))
        #expect(mutant.tokens(viewMode: .sourceAccurate).map(\.text) != expectedTokens)
    }

    @Test("An output callback error is not treated as a model failure")
    func callbackFailure() {
        var visited: [Int] = []
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try _NativeMachineOperations.visitAlternatives([0, 1], emit: { (_: Int) in
                throw NativeMachineEvaluationError.noMatchingCase
            }) { alternative, emit in
                visited.append(alternative)
                try emit(alternative)
                if alternative == 0 { throw NativeMachineEvaluationError.divisionByZero }
            }
        }
        #expect(visited == [0])
    }
}
