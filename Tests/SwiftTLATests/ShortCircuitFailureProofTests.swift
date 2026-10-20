import Foundation
import SwiftParser
import SwiftSyntax
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Short-circuit failure preservation")
struct ShortCircuitFailureProofTests {
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
        let pattern = #"if try (_predicate[0-9]+\(\)) \{"#
        let changed = visitor.description.replacingOccurrences(
            of: pattern, with: "if !(try $1) {", options: .regularExpression)
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
              case .and = predicate.children[1].operation else {
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
            of: #"if try (_predicate[0-9]+\(\)) \{"#,
            with: "if !(try $1) {", options: .regularExpression)
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
            of: #"if try (_predicate[0-9]+\(\)) \{"#,
            with: "if !(try $1) {", options: .regularExpression)
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
            of: "guard !left else { return true }",
            with: "guard left else { return true }")
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
                of: index == 0 ? "guard left else" : "guard !left else",
                with: index == 0 ? "guard !left else" : "guard left else")
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
