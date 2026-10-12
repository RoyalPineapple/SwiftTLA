import Foundation
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
import Testing

@Suite("Choice evaluation failures")
struct ChoiceEvaluationFailureTests {
    @Test("A failing sole candidate is reported by both generated checking paths")
    func soleCandidateFailure() throws {
        let machine = try SingleCandidateDivisionFailureModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }

        let rendered = try SingleCandidateDivisionFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==") })
    }

    @Test("A failing candidate does not hide another candidate's successor")
    func mixedCandidateOutcome() throws {
        let machine = try MixedCandidateDivisionFailureModel.makeMachine()
        var states: [Int: Int] = [:]
        var edges: [(Int, Int)] = []
        var observedFailure = false
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                observedFailure = true
                #expect(source == 0 && action == .pick && reason == .divisionByZero)
            default: break
            }
        }
        #expect(observedFailure)
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))
        #expect(outcome.states == 2 && outcome.edges == 1)
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 1 && edges[0].0 == 0 && edges[0].1 == 1)

        let rendered = try MixedCandidateDivisionFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        let failure = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        #expect(failure.contains("__atomic_0 \\in 0..1"))
        let divisors = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroDivisor0 ==")
        })
        #expect(divisors.contains("__atomic_0 \\in {__atomic_0 \\in 0..1:"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/MixedCandidateDivisionFailureModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("A failing Either branch does not hide a successful branch")
    func eitherBranchOutcome() throws {
        let machine = try EitherBranchDivisionFailureModel.makeMachine()
        var states: [Int: Int] = [:]
        var edges: [(Int, Int)] = []
        var observedFailure = false
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                observedFailure = true
                #expect(source == 0 && action == .pick && reason == .divisionByZero)
            default: break
            }
        }
        #expect(observedFailure)
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))
        #expect(outcome.states == 2 && outcome.edges == 1)
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 1 && edges[0].0 == 0 && edges[0].1 == 1)

        let rendered = try EitherBranchDivisionFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/EitherBranchDivisionFailureModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("The emitted Swift visitor preserves both Either branches")
    func eitherBranchEmittedSwift() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "EitherBranchDivisionFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        let action = try #require(compiled.program.behavior.actions.first)
        guard compiled.program.behavior.actions.count == 1,
              case .or(let first, let second) = action.body,
              case .define(_, let quotient, _) = first,
              case .divide = quotient.operation,
              quotient.children.count == 2,
              case .value(.integer(1)) = quotient.children[0].operation,
              case .stateVariable(let divisor) = quotient.children[1].operation,
              divisor == compiled.program.layout.variables.first?.id,
              case .define(_, let one, _) = second,
              case .value(.integer(1)) = one.operation else {
            Issue.record("The source Either no longer lowers to the proved division-or-success rule")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let update = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let witness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/EitherBranchDivisionFailureSwiftWitness.txt")
            .standardizedFileURL
        let expected = try #require(Parser.parse(source: String(contentsOf: witness, encoding: .utf8))
            .statements.first?.item.as(FunctionDeclSyntax.self))
        let actualTokens = update.tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actualTokens == expected.tokens(viewMode: .sourceAccurate).map(\.text))

        let droppedBranch = Parser.parse(source: update.description.replacingOccurrences(
            of: "try _actionPart2(updates, { secondUpdates.append($0) })", with: "return"))
        let mutant = try #require(droppedBranch.statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(mutant.tokens(viewMode: .sourceAccurate).map(\.text) != actualTokens)
    }
}
