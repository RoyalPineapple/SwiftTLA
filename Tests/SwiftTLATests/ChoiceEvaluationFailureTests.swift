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

    @Test("An earlier Either failure wins when both branches fail differently")
    func eitherFailureOrder() throws {
        let machine = try EitherDistinctFailuresModel.makeMachine()
        #expect(machine.state.divisor == 0 && machine.state.modulus == -1 && machine.state.result == 0)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }

        let rendered = try EitherDistinctFailuresModel.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        let laterFailure = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLANegativeModuloDivisorFailure0 ==")
        })
        #expect(laterFailure.contains("divisor # 0"))
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/EitherDistinctFailuresModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("An earlier arithmetic failure suppresses a later choice failure")
    func eitherMixedFailureOrder() throws {
        let machines = try EitherChoiceAfterDivisionFailureModel.initialMachines()
        #expect(Set(machines.map(\.state.divisor)) == [0, 1])
        let firstFailure = try #require(machines.first { $0.state.divisor == 0 })
        let laterFailure = try #require(machines.first { $0.state.divisor == 1 })
        #expect(firstFailure.state.result == 0 && laterFailure.state.result == 0)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try firstFailure.successors(for: .pick)
        }
        var states: [Int: Int] = [:]
        var edges: [(Int, Int)] = []
        var observedFailure = false
        let outcome = try MachineValidator.run(initialMachines: [laterFailure], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                observedFailure = true
                #expect(source == 0 && action == .pick && reason == .noSatisfyingChoice)
            default: break
            }
        }
        #expect(observedFailure)
        #expect(outcome.completion == .evaluationFailure(.noSatisfyingChoice))
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 1 && edges[0] == (0, 1))

        let rendered = try EitherChoiceAfterDivisionFailureModel.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        let laterFailurePredicate = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLAChoiceFailure0 ==")
        })
        #expect(laterFailurePredicate.contains("divisor # 0"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/EitherChoiceAfterDivisionFailureModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("Emitted Swift visits both kinds of later failure")
    func eitherFailureOrderEmittedSwift() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        for (name, witnessName) in [
            ("EitherDistinctFailuresModel", "EitherDistinctFailuresSwiftWitness.txt"),
            ("EitherChoiceAfterDivisionFailureModel", "EitherChoiceAfterDivisionFailureSwiftWitness.txt")
        ] {
            let declaration = try #require(source.statements.compactMap {
                $0.item.as(StructDeclSyntax.self)
            }.first { $0.name.text == name })
            let compiled = try TLASpecVerifier.parseAndVerify(declaration)
            var emitter = NativeSwiftEmitter(model: compiled)
            let update = try #require(try emitter.machineMembers().first {
                $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
            })
            let witness = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../../Verification/Semantics/\(witnessName)")
                .standardizedFileURL
            let expected = try #require(Parser.parse(source: String(contentsOf: witness, encoding: .utf8))
                .statements.first?.item.as(FunctionDeclSyntax.self))
            #expect(update.tokens(viewMode: .sourceAccurate).map(\.text)
                == expected.tokens(viewMode: .sourceAccurate).map(\.text))
        }
    }

    @Test("A failing candidate retains another candidate's successor in both outputs")
    func candidateChoiceFailure() throws {
        let machine = try CandidateChoiceFailureModel.makeMachine()
        var states: [Int: Int] = [:]
        var edges: [(Int, Int)] = []
        var failures: [NativeMachineEvaluationError] = []
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(_, let action, let reason):
                #expect(action == .pick)
                failures.append(reason)
            default: break
            }
        }
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 1 && edges[0] == (0, 1))
        #expect(failures == [.noSatisfyingChoice])
        #expect(outcome.completion == .evaluationFailure(.noSatisfyingChoice))

        let rendered = try CandidateChoiceFailureModel.render()
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CandidateChoiceFailureModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "CandidateChoiceFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: compiled)
        let update = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let witness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/CandidateChoiceFailureSwiftWitness.txt")
            .standardizedFileURL
        let expected = try #require(Parser.parse(source: String(contentsOf: witness, encoding: .utf8))
            .statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(update.tokens(viewMode: .sourceAccurate).map(\.text)
            == expected.tokens(viewMode: .sourceAccurate).map(\.text))
    }

    @Test("A Let binding preserves a choice failure in its body")
    func boundBodyChoiceFailure() throws {
        let machines = try BoundBodyChoiceFailureModel.initialMachines()
        #expect(Set(machines.map(\.state.source)) == [0, 1])
        let failing = try #require(machines.first { $0.state.source == 0 })
        let succeeding = try #require(machines.first { $0.state.source == 1 })
        #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
            try failing.successors(for: .pick)
        }
        let successors = try succeeding.successors(for: .pick)
        let successor = try #require(successors.first)
        #expect(successors.count == 1)
        #expect(successor.state.source == 1 && successor.state.result == 1)

        let rendered = try BoundBodyChoiceFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let failure = try #require(rendered.tlaBundle.root.tla.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAChoiceFailure0 ==")
        })
        #expect(failure.contains("LET"))
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/BoundBodyChoiceFailureModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))

        let sourceFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: sourceFile, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "BoundBodyChoiceFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        let action = try #require(compiled.program.behavior.actions.first)
        guard compiled.program.behavior.actions.count == 1,
              case .define(let bound, let boundValue, let body) = action.body,
              case .stateVariable(let sourceID) = boundValue.operation,
              sourceID == compiled.program.layout.variables.first?.id,
              case .define(_, let selected, _) = body,
              case .choose = selected.operation,
              selected.children.count == 2,
              case .equal = selected.children[1].operation,
              selected.children[1].children.count == 2,
              case .boundValue(let captured) = selected.children[1].children[1].operation,
              captured == bound else {
            Issue.record("The source Let no longer lowers to the proved bound-body choice rule")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let update = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let witness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/BoundBodyChoiceFailureSwiftWitness.txt")
            .standardizedFileURL
        let binderPattern = try Regex(#"___binder_SpecParser_[0-9]+_0_2"#)
        let normalized = update.description.replacing(binderPattern, with: "__PROOF_MEMBER__")
        let actualTokens = Parser.parse(source: normalized).tokens(viewMode: .sourceAccurate).map(\.text)
        let expectedTokens = try Parser.parse(source: String(contentsOf: witness, encoding: .utf8))
            .tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actualTokens == expectedTokens)
    }

    @Test("A fallible If condition preserves failures in its selected branch")
    func conditionalChoiceThenDivisionFailure() throws {
        let machines = try ConditionalChoiceThenDivisionFailureModel.initialMachines()
        #expect(machines.count == 4)
        for machine in machines {
            if machine.state.selector == 0 {
                #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
                    try machine.successors(for: .compute)
                }
            } else if machine.state.divisor == 0 {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.successors(for: .compute)
                }
            } else {
                let successors = try machine.successors(for: .compute)
                #expect(successors.count == 1)
                #expect(successors.first?.state.result == 1)
            }
        }

        let rendered = try ConditionalChoiceThenDivisionFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAChoiceFailure0 ==") })
        let division = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        #expect(division.contains("IF"))
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

        let droppedSuccessfulBranch = Parser.parse(source: update.description.replacingOccurrences(
            of: "try _actionPart1(updates, branchEmit)", with: "return"))
        let mutant = try #require(droppedSuccessfulBranch.statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(mutant.tokens(viewMode: .sourceAccurate).map(\.text) != actualTokens)
    }
}
