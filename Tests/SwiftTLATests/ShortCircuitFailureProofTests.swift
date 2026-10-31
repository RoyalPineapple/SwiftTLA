import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Short-circuit failure preservation")
struct ShortCircuitFailureProofTests {
    @Test("Actual Boolean TLA output rejects changed selection, definedness, and failure payloads")
    func renderedBooleanOutcomes() throws {
        for specification in [ShortCircuitFailureModel.spec, BranchingBooleanFailureModel.spec,
                              ConditionalBooleanAssignmentModel.spec] {
            let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
            let output = try program.renderModule()
            let renderer = CompiledTLARenderer(moduleName: program.moduleName,
                reservedNames: [], layout: program.layout,
                bindings: .init(binders: program.binderNames), operators: .init(),
                actions: program.behavior.actions, functions: program.functions,
                enums: program.enums, parameterDomains: program.behavior.parameterDomains)
            for action in program.behavior.actions {
                let actual = try renderer.action(action.body)
                func verify(_ body: String) throws {
                    try StraightLineRenderedActionCheck.verify(action.body, rendered: body,
                        layout: program.layout, binders: program.binderNames, required: true)
                }
                try verify(actual)
                let reversedCondition = actual.replacingOccurrences(
                    of: "IF enabled THEN", with: "IF (~enabled) THEN")
                #expect(reversedCondition != actual)
                #expect(throws: CompilationDiagnostic.self) { try verify(reversedCondition) }

                let mutations = [
                    ("THEN ((1 % divisor) = 0) ELSE FALSE", "THEN TRUE ELSE ((1 % divisor) = 0)"),
                    ("THEN TRUE ELSE ((1 % divisor) = 0)", "THEN ((1 % divisor) = 0) ELSE FALSE"),
                    ("(~ready)", "ready"),
                    ("(~(IF ready THEN TRUE ELSE FALSE))", "(IF ready THEN TRUE ELSE FALSE)"),
                    ("divisor # 0", "divisor # 1")
                ]
                for (before, after) in mutations where actual.contains(before) {
                    let mutant = actual.replacingOccurrences(of: before, with: after)
                    #expect(throws: CompilationDiagnostic.self) { try verify(mutant) }
                }
            }
            func verifyFailures(_ source: String, _ declarations: [String]) throws {
                try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
                    module: source, failureDeclarations: declarations,
                    evaluationInvariant: "__SwiftTLAEvaluationOK",
                    configuration: output.configuration, renderer: renderer)
            }
            try verifyFailures(output.renderedModuleSource, output.evaluationFailureDeclarations)
            for prefix in ["__SwiftTLADivisionByZeroFailure0", "__SwiftTLADivisionByZeroDivisor0",
                           "__SwiftTLANegativeModuloDivisorFailure0", "__SwiftTLANegativeModuloDivisorValue0",
                           "__SwiftTLAAnyEvaluationFailure0"] {
                let original = try #require(output.evaluationFailureDeclarations.first {
                    $0.hasPrefix("\(prefix) == ")
                })
                let changed = "\(prefix) == \(prefix.contains("Failure") ? "TRUE" : "0")"
                #expect(changed != original)
                #expect(throws: CompilationDiagnostic.self) {
                    try verifyFailures(output.renderedModuleSource.replacingOccurrences(of: original, with: changed),
                        output.evaluationFailureDeclarations.map { $0 == original ? changed : $0 })
                }
            }
        }
    }

    @Test("Boolean assignment output rejects a reversed selected branch")
    func nestedConditionalAssignment() throws {
        let machines = try ConditionalBooleanAssignmentModel.initialMachines()
        #expect(machines.count == 8)
        for machine in machines {
            let state = machine.state
            if state.enabled && state.ready && state.divisor == 0 {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.successors(for: .advance)
                }
            } else {
                let successors = try machine.successors(for: .advance)
                #expect(successors.count == 1)
                let successor = try #require(successors.first)
                let expected = state.enabled
                    ? state.ready && state.divisor == 1
                    : !state.ready
                #expect(successor.state.result == expected)
            }
        }

        let compiled = try ConditionalBooleanAssignmentModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var pending = [action.body]
        var foundMixedCapture = false
        while let node = pending.popLast() {
            switch node {
            case .define(_, let value, let child):
                if case .ifThenElse = value.operation,
                   value.children.count == 3,
                   case .and = value.children[1].operation {
                    foundMixedCapture = true
                }
                pending.append(child)
            case .assign: break
            case .and(let left, let right), .or(let left, let right):
                pending += [left, right]
            case .ifElse(_, let yes, let no): pending += [yes, no]
            case .existsAction(_, _, let child): pending.append(child)
            case .guard_, .unchanged: break
            }
        }
        #expect(foundMixedCapture)

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "ConditionalBooleanAssignmentModel", program: program))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames,
            parts: parts.writes, conditions: parts.conditions)
        let pattern = #"booleanIf\(\{ try (_predicate[0-9]+\(\)) \},"#
        let changed = visitor.description.replacingOccurrences(
            of: pattern,
            with: "booleanIf({ try _NativeMachineOperations.booleanNot { try $1 } },",
            options: .regularExpression)
        #expect(changed != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: changed)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("A Boolean assignment selected the opposite branch")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
    }

    @Test("Nested conditional guards reject a reversed emitted branch")
    func nestedConditionalBranch() throws {
        let machines = try BranchingBooleanFailureModel.initialMachines()
        #expect(machines.count == 8)
        for machine in machines {
            let state = machine.state
            if state.enabled && state.ready && state.divisor == 0 {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.successors(for: .advance)
                }
            } else {
                let successors = try machine.successors(for: .advance)
                let enabled = state.enabled
                    ? state.ready && state.divisor == 1
                    : !state.ready
                #expect(successors.count == (enabled ? 1 : 0))
            }
        }

        let compiled = try BranchingBooleanFailureModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        guard case .and(let guarded, _) = action.body,
              case .guard_(let predicate) = guarded,
              case .ifThenElse = predicate.operation,
              predicate.children.count == 3,
              case .and = predicate.children[1].operation,
              case .not = predicate.children[2].operation,
              predicate.children[2].children.count == 1,
              case .and = predicate.children[2].children[0].operation else {
            Issue.record("The source guard no longer lowers to the checked mixed Boolean tree")
            return
        }
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "BranchingBooleanFailureModel", program: program))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames,
            parts: parts.writes, conditions: parts.conditions)
        let changed = visitor.description.replacingOccurrences(
            of: #"booleanIf\(\{ try (_predicate[0-9]+\(\)) \},"#,
            with: "booleanIf({ try _NativeMachineOperations.booleanNot { try $1 } },",
            options: .regularExpression)
        #expect(changed != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: changed)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("A nested conditional selected the opposite branch")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let missingNegation = visitor.description.replacingOccurrences(
            of: #"return try _NativeMachineOperations\.booleanNot \{ try (_predicate[0-9]+\(\)) \}"#,
            with: "return try $1", options: .regularExpression)
        #expect(missingNegation != visitor.description)
        let wrongNegation = try #require(Parser.parse(source: missingNegation)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongNegation, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("Negation no longer preserves the selected Boolean outcome")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let changedModulo = visitor.description.replacingOccurrences(
            of: "_NativeMachineOperations.modulo(", with: "_NativeMachineOperations.divide(")
        #expect(changedModulo != visitor.description)
        let wrongModulo = try #require(Parser.parse(source: changedModulo)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongModulo, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("A nested Boolean guard accepted a changed modulo operation")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
        let rendered = try BranchingBooleanFailureModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/BranchingBooleanFailureModel.tla")
            .standardizedFileURL
        let formal = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered == formal, "Actual generated TLA+: \(rendered)")
    }

    @Test("Conditional Boolean leaves preserve selected failures and generated output")
    func conditionalBooleanLeaf() throws {
        let machines = try ConditionalShortCircuitFailureModel.initialMachines()
        #expect(machines.count == 8)
        for machine in machines {
            let state = machine.state
            if state.enabled && !state.ready && state.divisor == 0 {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.successors(for: .advance)
                }
            } else {
                let successors = try machine.successors(for: .advance)
                let enabled = state.enabled && (state.ready || state.divisor == 1)
                #expect(successors.count == (enabled ? 1 : 0))
                #expect(successors.allSatisfy {
                    $0.state.result == 1 && $0.state.enabled == state.enabled &&
                        $0.state.ready == state.ready && $0.state.divisor == state.divisor
                })
            }
        }

        let compiled = try ConditionalShortCircuitFailureModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        guard case .and(let guarded, _) = action.body,
              case .guard_(let predicate) = guarded,
              case .and = predicate.operation,
              predicate.children.count == 2,
              case .ifThenElse = predicate.children[1].operation else {
            Issue.record("The source conditional no longer lowers to the checked Boolean leaf")
            return
        }
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "ConditionalShortCircuitFailureModel", program: program))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames,
            parts: parts.writes, conditions: parts.conditions)
        let changed = visitor.description.replacingOccurrences(
            of: #"booleanIf\(\{ try (_predicate[0-9]+\(\)) \},"#,
            with: "booleanIf({ try _NativeMachineOperations.booleanNot { try $1 } },",
            options: .regularExpression)
        #expect(changed != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: changed)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("A conditional Boolean leaf changed its selected branch")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }

        let rendered = try ConditionalShortCircuitFailureModel.render().tlaBundle.root.tla
        let normalized = rendered.replacingOccurrences(
            of: "MODULE ConditionalShortCircuitFailureModel",
            with: "MODULE NestedShortCircuitFailureModel")
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/NestedShortCircuitFailureModel.tla")
            .standardizedFileURL
        let formal = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(normalized == formal, "Actual generated TLA+: \(rendered)")
    }

    @Test("A generated membership condition rejects a changed finite set")
    func membershipConditionalOutput() throws {
        let compiled = try GeneratedMembershipConditionalFailureModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "GeneratedMembershipConditionalFailureModel", program: program))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames,
            parts: parts.writes, conditions: parts.conditions)

        let changed = visitor.description.replacingOccurrences(
            of: "Set<Int>([1])", with: "Set<Int>([2])")
        #expect(changed != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: changed)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("The emitted condition changed its compiled membership set")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.conditional."))
        }
    }

    @Test("A configured membership leaf and its Boolean branch retain their compiled operands")
    func symbolicMembershipBranchOutput() throws {
        let compiled = try SymbolicConfigurationModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SymbolicConfigurationModel", program: program))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames,
            parts: parts.writes, conditions: parts.conditions)

        let changed = visitor.description.replacingOccurrences(
            of: "_NativeMachineOperations.booleanAnd(",
            with: "_NativeMachineOperations.booleanOr(")
        #expect(changed != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: changed)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("The symbolic leaf hid a reversed Boolean operation")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }

        let changedMember = visitor.description.replacingOccurrences(
            of: ".contains(1)", with: ".contains(2)")
        #expect(changedMember != visitor.description)
        let wrongMemberVisitor = try #require(Parser.parse(source: changedMember)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongMemberVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("The configured membership leaf changed its compiled member")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }
    }

    @Test("Nested Boolean steps retain skipped failures and complete output links")
    func nestedBooleanOutcome() throws {
        let machines = try NestedShortCircuitFailureModel.initialMachines()
        #expect(machines.count == 8)
        for machine in machines {
            let state = machine.state
            if state.enabled && !state.ready && state.divisor == 0 {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.successors(for: .advance)
                }
            } else {
                let successors = try machine.successors(for: .advance)
                let enabled = state.enabled && (state.ready || state.divisor == 1)
                #expect(successors.count == (enabled ? 1 : 0))
                #expect(successors.allSatisfy {
                    $0.state.result == 1 && $0.state.enabled == state.enabled &&
                        $0.state.ready == state.ready && $0.state.divisor == state.divisor
                })
            }
        }

        let compiled = try NestedShortCircuitFailureModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "NestedShortCircuitFailureModel", program: program))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body,
            program: program, stateFields: emitter.stateMemberNames,
            parts: parts.writes, conditions: parts.conditions)
        let changed = visitor.description.replacingOccurrences(
            of: "_NativeMachineOperations.booleanOr(",
            with: "_NativeMachineOperations.booleanAnd(")
        #expect(changed != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: changed)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("A nested disjunction evaluated its skipped right operand")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.guard."))
        }

        let rendered = try NestedShortCircuitFailureModel.render().tlaBundle.root.tla
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/NestedShortCircuitFailureModel.tla")
            .standardizedFileURL
        let formal = try String(contentsOf: proofInput, encoding: .utf8)
        #expect(rendered == formal, "Actual generated TLA+: \(rendered)")
    }

    @Test("Generated Boolean steps match the proof inputs")
    func generatedBooleanStepProofInputs() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "ShortCircuitFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        func guards(in action: CompiledActionExpr) -> [CompiledExpression] {
            switch action {
            case .guard_(let value): return [value]
            case .existsAction(_, _, let body), .define(_, _, let body): return guards(in: body)
            case .ifElse(_, let yes, let no), .and(let yes, let no), .or(let yes, let no):
                return guards(in: yes) + guards(in: no)
            case .assign, .unchanged: return []
            }
        }
        let actions = compiled.program.behavior.actions
        #expect(actions.count == 2)
        let conjunction = try #require(actions.first)
        let disjunction = try #require(actions.last)
        let conjunctionGuard = try #require(guards(in: conjunction.body).first)
        let disjunctionGuard = try #require(guards(in: disjunction.body).first)
        guard case .and = conjunctionGuard.operation,
              case .or = disjunctionGuard.operation else {
            Issue.record("The source Boolean steps no longer lower to the proved short-circuit rules")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let proofDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics")
            .standardizedFileURL
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map(\.text)
        }
        for index in 0..<2 {
            let visitor = try #require(members.first {
                $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(index)"
            })
            let name = index == 0
                ? "ShortCircuitConjunctionSwiftVisitor.txt"
                : "ShortCircuitDisjunctionSwiftVisitor.txt"
            let witness = try String(contentsOf: proofDirectory.appendingPathComponent(name),
                encoding: .utf8)
            #expect(tokens(visitor.description) == tokens(witness))
            let reversed = visitor.description.replacingOccurrences(
                of: index == 0 ? "_NativeMachineOperations.booleanAnd(" : "_NativeMachineOperations.booleanOr(",
                with: index == 0 ? "_NativeMachineOperations.booleanOr(" : "_NativeMachineOperations.booleanAnd(")
            #expect(reversed != visitor.description)
            #expect(tokens(reversed) != tokens(witness))
            let action = actions[index]
            let parts = try emitter.actionFunctions(action.body)
            let wrongVisitor = try #require(Parser.parse(source: reversed)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body,
                    program: compiled.program, stateFields: emitter.stateMemberNames,
                    parts: parts.writes, conditions: parts.conditions)
                Issue.record("A short-circuit guard reversed its compiled left test")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.guard."))
            }
            let changedLeaf = visitor.description.replacingOccurrences(of: "== 0)", with: "== 1)")
            #expect(changedLeaf != visitor.description)
            let wrongLeaf = try #require(Parser.parse(source: changedLeaf)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(wrongLeaf, action: action.body,
                    program: compiled.program, stateFields: emitter.stateMemberNames,
                    parts: parts.writes, conditions: parts.conditions)
                Issue.record("A short-circuit guard changed its compiled right operand")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.guard."))
            }
        }
        let rendered = try ShortCircuitFailureModel.render()
        let formal = try String(contentsOf:
            proofDirectory.appendingPathComponent("ShortCircuitFailureModel.tla"),
            encoding: .utf8)
        #expect(rendered.tlaBundle.root.tla == formal)
        let eagerConjunction = formal.replacingOccurrences(
            of: #"__SwiftTLADivisionByZeroFailure0 == ~((IF enabled THEN divisor # 0 ELSE TRUE))"#,
            with: #"__SwiftTLADivisionByZeroFailure0 == ~((IF enabled THEN divisor # 0 ELSE FALSE))"#)
        #expect(eagerConjunction != formal)
        #expect(eagerConjunction != rendered.tlaBundle.root.tla)
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
    }
}
