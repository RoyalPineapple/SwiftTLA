import Foundation
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
import Testing

@Suite("Choice evaluation failures")
struct ChoiceEvaluationFailureTests {
    @Test("The first failing Choose candidate determines the reported failure")
    func orderedCandidateFailures() throws {
        let machine = try OrderedCandidateFailuresModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }
        #expect(machine.state.modulus == -1 && machine.state.result == 0)

        let rendered = try OrderedCandidateFailuresModel.render()
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        let division = try #require(declarations.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        let modulo = try #require(declarations.first {
            $0.hasPrefix("__SwiftTLANegativeModuloDivisorFailure0 ==")
        })
        #expect(division.contains("__SwiftTLAFirstFailingCandidate"))
        #expect(modulo.contains("__SwiftTLAFirstFailingCandidate"))
        #expect(division.contains(" <= __SwiftTLAEarlierCandidate"))
        #expect(modulo.contains(" <= __SwiftTLAEarlierCandidate"))
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
    }

    @Test("Finite enum Choose candidates use canonical failure order")
    func orderedEnumCandidateFailures() throws {
        let machine = try OrderedEnumCandidateFailuresModel.makeMachine()
        #expect(machine.state.divisor == 0)
        #expect(machine.state.modulus == -1)
        #expect(machine.state.result == 0)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }
        var states = 0
        var edges = 0
        var failures = 0
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 1,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state: states += 1
            case .edge: edges += 1
            case .evaluationFailure(let source, let action, let reason):
                failures += 1
                #expect(source == 0 && action == .pick && reason == .divisionByZero)
            default: break
            }
        }
        #expect(states == 1 && edges == 0 && failures == 1)
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))

        let rendered = try OrderedEnumCandidateFailuresModel.render()
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/OrderedEnumCandidateFailuresModel.tla")
            .standardizedFileURL
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        let division = try #require(declarations.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        let modulo = try #require(declarations.first {
            $0.hasPrefix("__SwiftTLANegativeModuloDivisorFailure0 ==")
        })
        #expect(division.contains("__SwiftTLAFirstFailingCandidate"))
        #expect(modulo.contains("__SwiftTLAFirstFailingCandidate"))
        #expect(division.contains("= \"alpha\" -> 0"))
        #expect(modulo.contains("= \"zed\" -> 1"))

        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "OrderedEnumCandidateFailuresModel" })
        var emitter = NativeSwiftEmitter(model: try TLASpecVerifier.parseAndVerify(declaration))
        let update = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let witness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/OrderedEnumCandidateFailureSwiftWitness.txt")
            .standardizedFileURL
        let expected = try #require(Parser.parse(source: String(contentsOf: witness, encoding: .utf8))
            .statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(update.tokens(viewMode: .sourceAccurate).map(\.text)
            == expected.tokens(viewMode: .sourceAccurate).map(\.text))
    }

    @Test("Parameterized string candidates retain the first failure on both outputs")
    func parameterizedStringCandidateFailures() throws {
        let scenarios = try ParameterizedStringCandidateFailuresModel.validationScenarios()
        #expect(scenarios.count == 2)
        let scenario = try #require(scenarios.first)
        let machine = try #require(scenario.initialMachines().first)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }
        let later = try #require(scenarios.last?.initialMachines().first)
        #expect(throws: NativeMachineEvaluationError.negativeModuloDivisor(-1)) {
            try later.successors(for: .pick)
        }

        let rendered = try scenario.render()
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        let domain = try #require(declarations.first {
            $0.hasPrefix("ASSUME members \\in ")
        })
        #expect(domain.contains("\"alpha\"") && domain.contains("\"zed\""))
        let division = try #require(declarations.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        let modulo = try #require(declarations.first {
            $0.hasPrefix("__SwiftTLANegativeModuloDivisorFailure0 ==")
        })
        #expect(division.contains("__SwiftTLAFirstFailingCandidate"))
        #expect(modulo.contains("__SwiftTLAFirstFailingCandidate"))
        #expect(division.contains("= \"alpha\" -> 0"))
        #expect(modulo.contains("= \"zed\" -> 1"))
    }

    @Test("Finite model-value parameters use one first-failure order in Swift and TLA+")
    func parameterizedModelValueCandidateFailures() throws {
        let scenarios = try ParameterizedModelValueCandidateFailuresModel.validationScenarios()
        #expect(scenarios.count == 2)
        let both = try #require(scenarios.first)
        let machine = try #require(both.initialMachines().first)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }
        let later = try #require(scenarios.last?.initialMachines().first)
        #expect(throws: NativeMachineEvaluationError.negativeModuloDivisor(-1)) {
            try later.successors(for: .pick)
        }

        let rendered = try both.render()
        let failures = rendered.tlaBundle.root.tla.split(separator: "\n").filter {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
                || $0.hasPrefix("__SwiftTLANegativeModuloDivisorFailure0 ==")
        }
        #expect(failures.count == 2)
        #expect(failures.allSatisfy { $0.contains("__SwiftTLAFirstFailingCandidate") })
        #expect(failures.allSatisfy { $0.contains("= a -> 0") && $0.contains("= z -> 1") })
    }

    @Test("Unranked state-dependent string candidates cannot claim ordered TLA failure parity")
    func stateDependentStringCandidateFailureOrder() throws {
        let machine = try StateDependentStringCandidateFailuresModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }
        do {
            _ = try StateDependentStringCandidateFailuresModel.render()
            Issue.record("TLA+ export must reject an unranked first-failure order")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unsupportedCanonicalCandidateOrder)
            #expect(diagnostic.stage == .rendering)
        }
    }

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
        var failureSources: [Int] = []
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                failureSources.append(source)
                #expect(action == .pick && reason == .divisionByZero)
            default: break
            }
        }
        #expect(failureSources == [0, 1])
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))
        #expect(outcome.states == 2 && outcome.edges == 2)
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 2 && edges[0] == (0, 1) && edges[1] == (1, 1))

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
        #expect(divisors.contains("__SwiftTLAFirstFailingCandidate"))
        #expect(divisors.contains(" <= __SwiftTLAEarlierCandidate"))
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
        var failureSources: [Int] = []
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                failureSources.append(source)
                #expect(action == .pick && reason == .divisionByZero)
            default: break
            }
        }
        #expect(failureSources == [0, 1])
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))
        #expect(outcome.states == 2 && outcome.edges == 2)
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 2 && edges[0] == (0, 1) && edges[1] == (1, 1))

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
        var failureSources: [Int] = []
        let outcome = try MachineValidator.run(initialMachines: [laterFailure], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                failureSources.append(source)
                #expect(action == .pick && reason == .noSatisfyingChoice)
            default: break
            }
        }
        #expect(failureSources == [0, 1])
        #expect(outcome.completion == .evaluationFailure(.noSatisfyingChoice))
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 2 && edges[0] == (0, 1) && edges[1] == (1, 1))

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
        var failures: [(Int, NativeMachineEvaluationError)] = []
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.result
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                #expect(action == .pick)
                failures.append((source, reason))
            default: break
            }
        }
        #expect(states == [0: 0, 1: 1])
        #expect(edges.count == 2 && edges[0] == (0, 1) && edges[1] == (1, 1))
        #expect(failures.count == 2 && failures[0].0 == 0 && failures[1].0 == 1)
        #expect(failures.allSatisfy { $0.1 == .noSatisfyingChoice })
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
    func conditionalChoiceThenModuloFailure() throws {
        let machines = try ConditionalChoiceThenModuloFailureModel.initialMachines()
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
                let successor = try #require(successors.first)
                #expect(successor.state.selector == 1)
                #expect(successor.state.divisor == 1)
                #expect(successor.state.result == 0)
            }
        }

        let rendered = try ConditionalChoiceThenModuloFailureModel.render()
        let sourceFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let syntax = Parser.parse(source: try String(contentsOf: sourceFile, encoding: .utf8))
        let declaration = try #require(syntax.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "ConditionalChoiceThenModuloFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        let action = try #require(compiled.program.behavior.actions.first)
        guard compiled.program.behavior.actions.count == 1,
              case .ifElse(let condition, _, _) = action.body,
              case .choose = condition.operation else {
            Issue.record("The source conditional no longer lowers to the proved choice-then-branch rule")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let members = try emitter.machineMembers()
        let update = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let swiftBinder = try Regex(#"___binder_SpecParser_[0-9]+_0_0"#)
        let normalizedSwift = update.description.replacing(swiftBinder, with: "__PROOF_MEMBER__")
        let swiftWitness = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ConditionalChoiceThenModuloFailureSwiftWitness.txt")
            .standardizedFileURL
        let actualTokens = Parser.parse(source: normalizedSwift).tokens(viewMode: .sourceAccurate).map(\.text)
        let expectedTokens = try Parser.parse(source: String(contentsOf: swiftWitness, encoding: .utf8))
            .tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actualTokens == expectedTokens)

        let tlaBinder = try Regex(#"__binder_SpecParser_[0-9]+_0"#)
        let normalizedTLA = rendered.tlaBundle.root.tla.replacing(tlaBinder, with: "__CONDITION_MEMBER__")
        let proofInput = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/ConditionalChoiceThenModuloFailureModel.tla")
            .standardizedFileURL
        #expect(normalizedTLA == (try String(contentsOf: proofInput, encoding: .utf8)))
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAChoiceFailure0 ==") })
        let division = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        #expect(division.contains("IF"))
    }

    @Test("Expression-level If reports only its selected branch's failure")
    func expressionConditionalFailures() throws {
        let machines = try ExpressionConditionalFailureModel.initialMachines()
        #expect(machines.count == 4)
        #expect(Set(machines.map { [$0.state.mode, $0.state.divisor] })
            == Set([[0, 0], [0, 1], [1, 0], [1, 1]]))
        #expect(machines.allSatisfy { $0.state.result == 0 })
        for machine in machines {
            if machine.state.mode == 1 {
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
                let successor = try #require(successors.first)
                #expect(successor.state.mode == 0)
                #expect(successor.state.divisor == 1)
                #expect(successor.state.result == 0)
            }
        }

        let rendered = try ExpressionConditionalFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAChoiceFailure0 ==") })
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==") })
    }

    @Test("Boolean expressions report right failures only when the right side is evaluated")
    func shortCircuitFailures() throws {
        let machines = try ShortCircuitFailureModel.initialMachines()
        #expect(machines.count == 4)
        #expect(Set(machines.map { [$0.state.enabled ? 1 : 0, $0.state.divisor] })
            == Set([[0, 0], [0, 1], [1, 0], [1, 1]]))
        #expect(machines.allSatisfy { $0.state.result == 0 })
        for machine in machines {
            let conjunction = {
                try machine.successors(for: .conjunction)
            }
            let disjunction = {
                try machine.successors(for: .disjunction)
            }
            if machine.state.divisor == 0 {
                if machine.state.enabled {
                    #expect(throws: NativeMachineEvaluationError.divisionByZero) { try conjunction() }
                    let successors = try disjunction()
                    #expect(successors.count == 1)
                    #expect(successors.first?.state.result == 2)
                } else {
                    #expect(try conjunction().isEmpty)
                    #expect(throws: NativeMachineEvaluationError.divisionByZero) { try disjunction() }
                }
            } else {
                #expect(try conjunction().count == (machine.state.enabled ? 1 : 0))
                let successors = try disjunction()
                #expect(successors.count == 1)
                #expect(successors.first?.state.result == 2)
            }
        }

        let rendered = try ShortCircuitFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==") })
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure1 ==") })
    }

    @Test("A successful action remains visible when another Boolean action fails")
    func successfulActionAlongsideFailure() throws {
        let initial = try #require(ShortCircuitFailureModel.initialMachines().first {
            $0.state.enabled && $0.state.divisor == 0
        })
        var results: [Int: Int] = [:]
        var edges: [(Int, ShortCircuitFailureModel.Action, Int)] = []
        var failures: [(Int, ShortCircuitFailureModel.Action, NativeMachineEvaluationError)] = []
        let outcome = try MachineValidator.run(initialMachines: [initial], maximumStates: 2,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): results[id] = snapshot.state.result
            case .edge(let source, let action, let target): edges.append((source, action, target))
            case .evaluationFailure(let source, let action, let reason):
                failures.append((source, action, reason))
            default: break
            }
        }
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))
        #expect(results[0] == 0)
        #expect(edges.contains { $0.0 == 0 && $0.1 == .disjunction && results[$0.2] == 2 })
        #expect(failures.contains { $0.0 == 0 && $0.1 == .conjunction && $0.2 == .divisionByZero })
    }

    @Test("A fallible Let value preserves an arithmetic failure in its body")
    func boundConditionalBodyFailure() throws {
        let machines = try BoundConditionalBodyFailureModel.initialMachines()
        #expect(machines.count == 4)
        for machine in machines {
            if machine.state.mode == 1 {
                #expect(throws: NativeMachineEvaluationError.noSatisfyingChoice) {
                    try machine.successors(for: .compute)
                }
            } else if machine.state.divisor == 0 {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.successors(for: .compute)
                }
            } else {
                let successor = try #require(machine.successors(for: .compute).first)
                #expect(successor.state.mode == 0)
                #expect(successor.state.divisor == 1)
                #expect(successor.state.result == 0)
            }
        }

        let rendered = try BoundConditionalBodyFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAChoiceFailure0 ==") })
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==") })
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
