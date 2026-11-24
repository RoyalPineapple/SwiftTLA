import Foundation
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
import Testing
import UpstreamParity

@Suite("Choice evaluation failures")
struct ChoiceEvaluationFailureTests {
    private func semanticFixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/\(name)")
            .standardizedFileURL
    }

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
        var failures: [NativeMachineEvaluationError] = []
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 1,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state: states += 1
            case .edge: edges += 1
            case .evaluationFailure(let source, let action, let reason):
                failures.append(reason)
                #expect(source == 0 && action == .pick)
            default: break
            }
        }
        #expect(states == 1 && edges == 0)
        #expect(failures == [.divisionByZero, .negativeModuloDivisor(-1)])
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))

        let rendered = try OrderedEnumCandidateFailuresModel.render()
        let proofInput = semanticFixture("OrderedEnumCandidateFailuresModel.tla")
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
        let witness = semanticFixture("OrderedEnumCandidateFailureSwiftWitness.txt")
        let expected = try #require(Parser.parse(source: nativeWitnessSource(String(contentsOf: witness, encoding: .utf8)))
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

    @Test("Finite parameter-derived dictionary keys preserve the first failure across generated outputs")
    func parameterDerivedDictionaryKeyFailureOrder() throws {
        let scenario = try #require(ParameterDerivedDictionaryKeyFailuresModel.validationScenarios().first)
        let machine = try #require(scenario.initialMachines().first)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }

        let rendered = try scenario.render()
        let failures = rendered.tlaBundle.root.tla.split(separator: "\n").filter {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
                || $0.hasPrefix("__SwiftTLANegativeModuloDivisorFailure0 ==")
        }
        #expect(failures.count == 2)
        #expect(failures.allSatisfy {
            $0.contains("__SwiftTLAFirstFailingCandidate")
                && $0.contains("= \"alpha\" -> 0")
                && $0.contains("= \"zed\" -> 1")
        })
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

        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        var classifiedCallbackErrors = 0
        #expect(throws: NativeMachineEvaluationError.emptySequence) {
            try machine.visitValidationOutcomes(checking: &context) { _, _ in
                throw NativeMachineEvaluationError.emptySequence
            } onEvaluationFailure: { _, _ in
                classifiedCallbackErrors += 1
                return true
            }
        }
        #expect(classifiedCallbackErrors == 0)

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
        let proofInput = semanticFixture("MixedCandidateDivisionFailureModel.tla")
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("A failing choice candidate retains its emitted Swift traversal")
    func mixedCandidateEmittedSwift() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "MixedCandidateDivisionFailureModel" })
        let compiled = try TLASpecVerifier.parseAndVerify(declaration)
        let action = try #require(compiled.program.behavior.actions.first)
        guard compiled.program.behavior.actions.count == 1,
              case .existsAction(let candidate, let domain, let body) = action.body,
              case .integerRange = domain.operation,
              domain.children.count == 2,
              case .value(.integer(0)) = domain.children[0].operation,
              case .value(.integer(1)) = domain.children[1].operation,
              case .define(_, let quotient, _) = body,
              case .divide = quotient.operation,
              quotient.children.count == 2,
              case .value(.integer(1)) = quotient.children[0].operation,
              case .boundValue(let divisor) = quotient.children[1].operation,
              divisor == candidate else {
            Issue.record("The authored choice no longer lowers to the proved candidate division")
            return
        }
        var emitter = NativeSwiftEmitter(model: compiled)
        let update = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let witness = semanticFixture("MixedCandidateDivisionFailureSwiftWitness.txt")
        let expected = try #require(Parser.parse(source: nativeWitnessSource(String(contentsOf: witness, encoding: .utf8)))
            .statements.first?.item.as(FunctionDeclSyntax.self))
        let expectedTokens = expected.tokens(viewMode: .sourceAccurate).map(\.text)
        let actualTokens = update.tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actualTokens == expectedTokens)
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(update, action: action.body,
            program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)

        let missingSuccessfulCandidate = update.description.replacingOccurrences(
            of: "integerRange(0, 1)", with: "integerRange(0, 0)")
        #expect(missingSuccessfulCandidate != update.description)
        let altered = try #require(Parser.parse(source: missingSuccessfulCandidate)
            .statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(altered.tokens(viewMode: .sourceAccurate).map(\.text) != expectedTokens)

        let reversedDivision = update.description.replacingOccurrences(
            of: "divide(_arithmetic1, _arithmetic0)",
            with: "divide(_arithmetic0, _arithmetic1)")
        #expect(reversedDivision != update.description)
        let reversed = try #require(Parser.parse(source: reversedDivision)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(reversed, action: action.body,
                program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("The generated division reversed the candidate and dividend")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.binding.1")
        }
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
        let proofInput = semanticFixture("EitherBranchDivisionFailureModel.tla")
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("An earlier Either failure wins when both branches fail differently")
    func eitherFailureOrder() throws {
        let machine = try EitherDistinctFailuresModel.makeMachine()
        #expect(machine.state.divisor == 0 && machine.state.modulus == -1 && machine.state.result == 0)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }

        var context = CheckingContext(registers: try machine.initialCheckingRegisters())
        var failures: [NativeMachineEvaluationError] = []
        var successes = 0
        let enabled = try machine.visitValidationOutcomes(checking: &context) { action, _ in
            #expect(action == .pick)
            successes += 1
            return true
        } onEvaluationFailure: { action, reason in
            #expect(action == .pick)
            failures.append(reason)
            return true
        }
        #expect(!enabled && successes == 0)
        #expect(failures == [.divisionByZero, .negativeModuloDivisor(-1)])

        var stoppedContext = CheckingContext(registers: try machine.initialCheckingRegisters())
        var stoppedFailures: [NativeMachineEvaluationError] = []
        _ = try machine.visitValidationOutcomes(checking: &stoppedContext) { _, _ in true }
            onEvaluationFailure: { _, reason in
                stoppedFailures.append(reason)
                return false
            }
        #expect(stoppedFailures == [.divisionByZero])
        var throwingContext = CheckingContext(registers: try machine.initialCheckingRegisters())
        #expect(throws: NativeMachineEvaluationError.emptySequence) {
            try machine.visitValidationOutcomes(checking: &throwingContext) { _, _ in true }
                onEvaluationFailure: { _, _ in throw NativeMachineEvaluationError.emptySequence }
        }

        let rendered = try EitherDistinctFailuresModel.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        let laterFailure = try #require(definitions.first {
            $0.hasPrefix("__SwiftTLANegativeModuloDivisorFailure0 ==")
        })
        #expect(laterFailure.contains("divisor # 0"))
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let proofInput = semanticFixture("EitherDistinctFailuresModel.tla")
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
        let proofInput = semanticFixture("EitherChoiceAfterDivisionFailureModel.tla")
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
    }

    @Test("Emitted Swift preserves ordered alternatives and their continuations")
    func eitherFailureOrderEmittedSwift() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("ChoiceEvaluationFailureFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let branchwiseFixture = fixture.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/UpstreamParity/ValidationModels/BranchwiseConjunctionFailureOrderModel.swift")
        let branchwiseAuthored = try String(contentsOf: branchwiseFixture, encoding: .utf8)
        let branchwiseSource = Parser.parse(source: branchwiseAuthored)
        for (name, witnessName) in [
            ("EitherDistinctFailuresModel", "EitherDistinctFailuresSwiftWitness.txt"),
            ("EitherChoiceAfterDivisionFailureModel", "EitherChoiceAfterDivisionFailureSwiftWitness.txt"),
            ("BranchwiseConjunctionFailureOrderModel", "BranchwiseConjunctionFailureOrderSwiftWitness.txt")
        ] {
            let owner = name == "BranchwiseConjunctionFailureOrderModel" ? branchwiseSource : source
            let declaration = try #require(owner.statements.compactMap {
                $0.item.as(StructDeclSyntax.self)
            }.first { $0.name.text == name })
            let compiled = try TLASpecVerifier.parseAndVerify(declaration)
            var emitter = NativeSwiftEmitter(model: compiled)
            let update = try #require(try emitter.machineMembers().first {
                $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
            })
            let witness = semanticFixture(witnessName)
            let expected = try #require(Parser.parse(source: nativeWitnessSource(String(contentsOf: witness, encoding: .utf8)))
                .statements.first?.item.as(FunctionDeclSyntax.self))
            #expect(update.tokens(viewMode: .sourceAccurate).map(\.text)
                == expected.tokens(viewMode: .sourceAccurate).map(\.text))
            if name == "BranchwiseConjunctionFailureOrderModel" {
                let action = try #require(compiled.program.behavior.actions.first)
                let writes = try emitter.actionFunctions(action).writes
                try verifyGeneratedActionWriteOutput(update, action: action.body,
                    program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
                let wrongSource = update.description.replacingOccurrences(
                    of: "if second { try _actionPart1(", with: "if second { try _actionPart2(")
                #expect(wrongSource != update.description)
                let wrong = try #require(Parser.parse(source: wrongSource)
                    .statements.first?.item.as(DeclSyntax.self))
                do {
                    try verifyGeneratedActionWriteOutput(wrong, action: action.body,
                        program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
                    Issue.record("A generated alternative silently replaced its later branch")
                } catch let diagnostic as CompilationDiagnostic {
                    #expect(diagnostic.path.hasPrefix("native.action.part.")
                        || diagnostic.path.hasPrefix("native.action.alternative."))
                }
                try checkOverwrittenBranchCapture(declaration)
                try checkSharedPrefixBranchCapture(branchwiseAuthored)
            }
        }
    }

    private func checkOverwrittenBranchCapture(_ source: StructDeclSyntax) throws {
        let authored = source.description
        let survivingWrite = "Assign(selected, to: 0)"
        let displacedWrite = "Assign(selected, to: 4)"
        try #require(authored.components(separatedBy: survivingWrite).count == 2)
        let overwritten = authored.replacingOccurrences(of: survivingWrite,
            with: "\(displacedWrite)\n                    \(survivingWrite)")
        let variant = try #require(Parser.parse(source: overwritten).statements.first?.item.as(StructDeclSyntax.self))
        let compiled = try TLASpecVerifier.parseAndVerify(variant)
        let action = try #require(compiled.program.behavior.actions.first)
        guard case .or(let left, let right) = action.body else {
            Issue.record("The compiler lost the authored alternative")
            return
        }
        func binders(_ branch: CompiledActionExpr) -> [BinderID] {
            var pending = branch
            var bindings: [BinderID] = []
            while case .define(let binding, _, let next) = pending {
                bindings.append(binding)
                pending = next
            }
            return bindings
        }
        let earlier = binders(left)
        let later = binders(right)
        try #require(earlier.count == 3 && later.count == 2)
        let selected = try #require(compiled.program.layout.variables.first { $0.declaration.name == "selected" }).id
        let result = try #require(compiled.program.layout.variables.first { $0.declaration.name == "result" }).id
        let branches = action.body.orderedAlternativeFailureRegions
        #expect(branches.map { $0.bindings.map(\.binder) } == [earlier, later])
        #expect(branches.map { $0.bindings.map(\.target) } == [[selected, selected, result], [selected, result]])

        // Both variants publish the same final frame. Only the first capture's target differs.
        try #require(overwritten.components(separatedBy: displacedWrite).count == 2)
        let otherTarget = overwritten.replacingOccurrences(of: displacedWrite, with: "Assign(result, to: 4)")
        let otherVariant = try #require(Parser.parse(source: otherTarget).statements.first?.item.as(StructDeclSyntax.self))
        let otherCompiled = try TLASpecVerifier.parseAndVerify(otherVariant)
        #expect(otherCompiled.program.identity != compiled.program.identity)

        let first = earlier[0]
        let second = earlier[1]
        let site = earlier[2].ordinal
        let firstName = try #require(compiled.program.binderNames[first])
        let secondName = try #require(compiled.program.binderNames[second])
        let firstLocal = "_\(firstName)_\(first.ordinal)"
        let secondLocal = "_\(secondName)_\(second.ordinal)"
        var emitter = NativeSwiftEmitter(model: compiled)
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(action.id.ordinal)"
        })
        let nativeEvent = "branch: 0, site: \(site), target: \(result.ordinal), before: "
            + "[(binding: \(first.ordinal), target: \(selected.ordinal), value: \(firstLocal)), "
            + "(binding: \(second.ordinal), target: \(selected.ordinal), value: \(secondLocal))], reason: failure"
        let nativeTokens = visitor.tokens(viewMode: .sourceAccurate).map(\.text).joined(separator: " ")
        let eventTokens = Parser.parse(source: "_record(\(nativeEvent))")
            .tokens(viewMode: .sourceAccurate).filter { $0.tokenKind != .endOfFile }
            .map(\.text).dropFirst(2).dropLast().joined(separator: " ")
        #expect(nativeTokens.contains(eventTokens))
        #expect(nativeTokens.contains("let \(firstLocal) = 4"))
        #expect(nativeTokens.contains("let \(secondLocal) = 0"))

        let module = try compiled.program.renderModule()
        let otherModule = try otherCompiled.program.renderModule()
        let relation = try #require(module.renderedModuleSource.split(separator: "\n").first { $0.hasPrefix("pick == ") })
        #expect(otherModule.renderedModuleSource.split(separator: "\n").first { $0.hasPrefix("pick == ") } == relation)
        let history = try #require(module.renderedModuleSource.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAActionFailureHistory\(action.id.ordinal) == ")
        })
        let divisionReceipt = "branch |-> 0, site |-> \(site), target |-> \(result.ordinal), "
            + "payload |-> <<\"divisionByZero\">>, before |-> (LET \(firstName) == 4 IN (LET \(secondName) == 0 IN "
            + "<<[binding |-> \(first.ordinal), target |-> \(selected.ordinal), value |-> \(firstName)], "
            + "[binding |-> \(second.ordinal), target |-> \(selected.ordinal), value |-> \(secondName)]>>))"
        #expect(history.contains(divisionReceipt))

        let parts = try emitter.actionFunctions(action)
        func verify(_ member: DeclSyntax) throws {
            try verifyGeneratedActionWriteOutput(member, action: action.body, program: compiled.program,
                stateFields: emitter.stateMemberNames, parts: parts.writes, conditions: parts.conditions)
        }
        try verify(visitor)

        let firstCapture = "(binding: \(first.ordinal), target: \(selected.ordinal), value: \(firstLocal))"
        let wrongCapture = "(binding: \(first.ordinal), target: \(result.ordinal), value: \(firstLocal))"
        try #require(firstCapture != wrongCapture)
        try #require(visitor.description.components(separatedBy: firstCapture).count == 2)
        let tampered = Parser.parse(source: visitor.description.replacingOccurrences(of: firstCapture, with: wrongCapture))
        try #require(!tampered.hasError)
        let wrongVisitor = try #require(tampered.statements.first?.item.as(DeclSyntax.self))
        do {
            try verify(wrongVisitor)
            Issue.record("The generated failure history accepted the wrong earlier assignment target")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.failures."))
            #expect(diagnostic.actual == "missing or changed assignment failure observation")
        }
    }

    private func checkSharedPrefixBranchCapture(_ authored: String) throws {
        let choice = "                Either {\n"
        try #require(authored.components(separatedBy: choice).count == 2)
        let prefixed = authored.replacingOccurrences(of: choice, with: "                Assign(selected, to: 4)\n\(choice)")
        let syntax = Parser.parse(source: prefixed)
        try #require(!syntax.hasError)
        let variant = try #require(syntax.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .first { $0.name.text == "BranchwiseConjunctionFailureOrderModel" })
        let found = try TLASpecVerifier.findSpec(in: variant.memberBlock.members, defaultName: variant.name.text)
        let literal = try #require(found)
        let members = variant.memberBlock.members
        let enums = try TLASpecVerifier.collectEnumVariables(from: members)
        let parser = ParserSession(sourceTypes: try TLASpecVerifier.sourceTypes(in: members, enums: enums))
        parser.sourceModelTypeName = variant.name.text
        let spec = parser.parseSpecClosure(named: literal.name, literal.closure)
        let (compilation, receipts) = try spec.compileRetainingAtomicBranchContinuations()
        let program = try CompiledProgram(inputs: parser.sourceTypeResolver.resolve(in: compilation))
        let rendered = try program.renderModule(retainingCaptureGuards: true)
        let pick = try #require(program.layout.actions.first { $0.declaration.name == "pick" })
        let action = program[pick.id]
        guard case .define(let prefix, let value, let continuation) = action.body,
              case .value(.integer(4)) = value.operation, case .or = continuation else {
            Issue.record("The compiler lost the single shared assignment before the alternative")
            return
        }
        let selected = try #require(program.layout.variables.first { $0.declaration.name == "selected" }).id
        let result = try #require(program.layout.variables.first { $0.declaration.name == "result" }).id
        let definitions = try CheckingSelectionEvidence.branchwiseContinuationDefinitions(
            authoredSource: prefixed, receipts: receipts, program: program, rendered: rendered)
            .split(separator: "\n").map(String.init)
        let sourceRow = TLAValue.record(TLARecord([
            .init("target", .string("selected")),
            .init("sourceTerm", .tuple([.tuple([.string("literal"), .int(4)])])),
            .init("reads", .tuple([])),
        ]))
        #expect(definitions.contains("BranchwiseContinuationPrefix == \(TLAValue.tuple([sourceRow]))"))
        #expect(definitions.contains("BranchwiseScheduledPrefixBindings == <<<<\(prefix.ordinal), \(selected.ordinal)>>>>"))

        let division = "Assign(result, to: 1 / divisor)"
        try #require(prefixed.components(separatedBy: division).count == 2)
        let wrongUploadedSource = prefixed.replacingOccurrences(of: division, with: "Assign(result, to: 1 / modulus)")
        let mismatch = EvidenceFormatError.invalidField(record: "Branchwise selected checks",
            field: "uploaded continuation assignment")
        #expect(throws: mismatch) {
            try CheckingSelectionEvidence.branchwiseContinuationDefinitions(
                authoredSource: wrongUploadedSource, receipts: receipts, program: program, rendered: rendered)
        }

        let regions = action.body.orderedAlternativeFailureRegions
        try #require(regions.map(\.armOrdinal) == [0, 1])
        try #require(regions.map { $0.bindings.count } == [3, 3])
        #expect(regions.map { $0.bindings.map(\.target) } == [[selected, selected, result], [selected, selected, result]])
        #expect(regions.allSatisfy { $0.bindings.filter { $0.binder == prefix }.map(\.target) == [selected]
            && $0.bindings.first?.binder == prefix })

        let macro = try MacroCompilation(typeName: variant.name.text, program: program)
        var emitter = NativeSwiftEmitter(model: macro)
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(action.id.ordinal)"
        })
        let parts = try emitter.actionFunctions(action)
        func verify(_ member: DeclSyntax) throws {
            try verifyGeneratedActionWriteOutput(member, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: parts.writes, conditions: parts.conditions)
        }
        try verify(visitor)
        let name = try #require(program.binderNames[prefix])
        let local = "_\(name)_\(prefix.ordinal)"
        let nativeRow = "(binding: \(prefix.ordinal), target: \(selected.ordinal), value: \(local))"
        #expect(visitor.description.components(separatedBy: "let \(local) = 4").count == 2)
        #expect(visitor.description.components(separatedBy: nativeRow).count == 4)

        let history = try #require(rendered.renderedModuleSource.split(separator: "\n").first {
            $0.hasPrefix("__SwiftTLAActionFailureHistory\(action.id.ordinal) == ")
        })
        let events = String(history).components(separatedBy: "[source |-> ").dropFirst()
        let sites = [(arm: 0, offset: 2), (arm: 1, offset: 1), (arm: 1, offset: 2)]
        var matched = 0
        for (arm, offset) in sites {
            let bindings = regions[arm].bindings
            let site = bindings[offset]
            let route = "branch |-> \(arm), site |-> \(site.binder.ordinal), target |-> \(site.target.ordinal),"
            let actual = events.filter { $0.contains(route) }
            try #require(!actual.isEmpty)
            let before = try bindings.prefix(offset).map { binding in
                let lexical = try #require(program.binderNames[binding.binder])
                return "[binding |-> \(binding.binder.ordinal), target |-> \(binding.target.ordinal), value |-> \(lexical)]"
            }.joined(separator: ", ")
            #expect(actual.allSatisfy { $0.contains("LET \(name) == 4 IN") && $0.contains("<<\(before)>>") })
            matched += actual.count
        }
        #expect(matched == events.count)

        let site = regions[1].bindings[1].binder.ordinal
        let record = "branch: 1, site: \(site), target: \(selected.ordinal), before: [\(nativeRow)]"
        try #require(visitor.description.components(separatedBy: record).count == 2)
        let wrong = "(binding: \(prefix.ordinal), target: \(result.ordinal), value: \(local))"
        let tampered = Parser.parse(source: visitor.description.replacingOccurrences(of: record,
            with: record.replacingOccurrences(of: nativeRow, with: wrong)))
        try #require(!tampered.hasError)
        let wrongVisitor = try #require(tampered.statements.first?.item.as(DeclSyntax.self))
        do {
            try verify(wrongVisitor)
            Issue.record("The generated failure accepted a wrong shared assignment target")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.failures."))
            #expect(diagnostic.actual == "missing or changed assignment failure observation")
        }

        let run = try runExternalGeneratedConsumer(prefixed + #"""

        @main struct ObserveBranchwisePrefix {
            static func main() throws {
                let initial = try BranchwiseConjunctionFailureOrderModel.initialMachines()
                for modulus in [0, 2] {
                    guard let machine = initial.first(where: { $0.state.divisor == 0 && $0.state.modulus == modulus })
                    else { fatalError("Missing authored initial state") }
                    let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 1,
                        checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { _ in }
                    guard let history = outcome.orderedActionFailureHistory, outcome.edges == 0,
                          outcome.completion == .evaluationFailure(.divisionByZero)
                    else { fatalError("The actual generated machine did not report the reached failures") }
                    for event in history {
                        let failure = event.failure
                        guard failure.reason == .divisionByZero else { fatalError("Unexpected failure reason") }
                        let captures = failure.before.map { "\($0.binding):\($0.target):\($0.value)" }.joined(separator: ",")
                        print("modulus=\(modulus) source=\(event.source) action=\(failure.action) branch=\(failure.branch) "
                            + "site=\(failure.site) target=\(failure.target) before=\(captures)")
                    }
                }
            }
        }
        """#)
        try #require(run.status == 0, Comment(rawValue: run.output))
        #expect(run.output.split(separator: "\n").map(String.init) == [
            "modulus=0 source=0 action=0 branch=0 site=2 target=3 before=0:2:4,1:2:0",
            "modulus=0 source=0 action=0 branch=1 site=3 target=2 before=0:2:4",
            "modulus=2 source=0 action=0 branch=0 site=2 target=3 before=0:2:4,1:2:0",
            "modulus=2 source=0 action=0 branch=1 site=4 target=3 before=0:2:4,3:2:1",
        ])
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
        #expect(outcome.orderedActionFailureHistory == nil)

        let rendered = try CandidateChoiceFailureModel.render()
        let proofInput = semanticFixture("CandidateChoiceFailureModel.tla")
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
        let witness = semanticFixture("CandidateChoiceFailureSwiftWitness.txt")
        let expected = try #require(Parser.parse(source: nativeWitnessSource(String(contentsOf: witness, encoding: .utf8)))
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
        let proofInput = semanticFixture("BoundBodyChoiceFailureModel.tla")
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
        let witness = semanticFixture("BoundBodyChoiceFailureSwiftWitness.txt")
        let binderPattern = try Regex(#"___binder_SpecParser_[0-9]+_0_2"#)
        let normalized = update.description.replacing(binderPattern, with: "__PROOF_MEMBER__")
        let actualTokens = Parser.parse(source: normalized).tokens(viewMode: .sourceAccurate).map(\.text)
        let expectedTokens = try Parser.parse(source: nativeWitnessSource(String(contentsOf: witness, encoding: .utf8)))
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
        let swiftWitness = semanticFixture("ConditionalChoiceThenModuloFailureSwiftWitness.txt")
        let actualTokens = Parser.parse(source: normalizedSwift).tokens(viewMode: .sourceAccurate).map(\.text)
        let expectedTokens = try Parser.parse(source: nativeWitnessSource(String(contentsOf: swiftWitness, encoding: .utf8)))
            .tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actualTokens == expectedTokens)

        let parts = try emitter.actionFunctions(action)
        try verifyGeneratedActionWriteOutput(update, action: action.body,
            program: compiled.program, stateFields: emitter.stateMemberNames, parts: parts.writes,
            conditions: parts.conditions)
        let predicate = try #require(parts.conditions.first?.value)
        let wrongConditionSource = update.description.replacingOccurrences(
            of: "visitConditional({ \(predicate) }", with: "visitConditional({ false }")
        #expect(wrongConditionSource != update.description)
        let wrongCondition = try #require(Parser.parse(source: wrongConditionSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(wrongCondition, action: action.body,
                program: compiled.program, stateFields: emitter.stateMemberNames,
                parts: parts.writes, conditions: parts.conditions)
            Issue.record("A generated conditional ignored its compiled predicate")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.conditional.0")
        }

        let tlaBinder = try Regex(#"__binder_SpecParser_[0-9]+_0"#)
        let normalizedTLA = rendered.tlaBundle.root.tla.replacing(tlaBinder, with: "__CONDITION_MEMBER__")
        let proofInput = semanticFixture("ConditionalChoiceThenModuloFailureModel.tla")
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

    @Test("A failing right conjunct retains successors from every left alternative")
    func conjunctiveAlternativesRetainSuccesses() throws {
        let machine = try ConjunctiveAlternativeFailureModel.makeMachine()
        var states: [Int: Int] = [:]
        var edges: [(Int, Int)] = []
        var failures: [(Int, NativeMachineEvaluationError)] = []
        let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 3,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
            switch event {
            case .state(let id, let snapshot, _, _, _): states[id] = snapshot.state.selected
            case .edge(let source, let action, let target):
                #expect(action == .pick)
                edges.append((source, target))
            case .evaluationFailure(let source, let action, let reason):
                #expect(action == .pick)
                failures.append((source, reason))
            default: break
            }
        }
        #expect(outcome.completion == .evaluationFailure(.divisionByZero))
        #expect(states[0] == -1)
        #expect(Set(edges.filter { $0.0 == 0 }.compactMap { states[$0.1] }) == Set([0, 1]))
        #expect(failures.contains { $0.0 == 0 && $0.1 == .divisionByZero })
    }

    @Test("A successful alternative reaches its failing continuation before a later alternative fails")
    func conjunctiveAlternativesKeepBranchwiseFailureOrder() throws {
        let machines = try BranchwiseConjunctionFailureOrderModel.initialMachines()
        #expect(machines.count == 8)
        for divisor in 0...1 {
            for modulus in [-1, 0, 1, 2] {
                let machine = try #require(machines.first {
                    $0.state.divisor == divisor && $0.state.modulus == modulus
                })
                #expect(machine.state.selected == -1 && machine.state.result == 0)
                var states: [Int: BranchwiseConjunctionFailureOrderModel.State] = [:]
                var initialIDs: [Int] = []
                var edges: [(Int, Int)] = []
                var recordedFailures: [(Int, NativeMachineEvaluationError)] = []
                let outcome = try MachineValidator.run(initialMachines: [machine], maximumStates: 3,
                    checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false) { event in
                    switch event {
                    case .state(let id, let snapshot, let initial, _, _):
                        states[id] = snapshot.state
                        if initial { initialIDs.append(id) }
                    case .edge(let source, let action, let target):
                        #expect(action == .pick)
                        edges.append((source, target))
                    case .evaluationFailure(let source, let action, let reason):
                        #expect(action == .pick)
                        recordedFailures.append((source, reason))
                    default: break
                    }
                }
                #expect(outcome.initialStates == 1)
                #expect(initialIDs.count == 1)
                let initialID = try #require(initialIDs.first)
                let targets = edges.filter { $0.0 == initialID }.map(\.1)
                let failures = recordedFailures.filter { $0.0 == initialID }.map(\.1)
                let successors = try targets.map { try #require(states[$0]) }
                #expect(successors.allSatisfy {
                    $0.divisor == divisor && $0.modulus == modulus && $0.result == 1
                })
                let expectedSelections: Set<Int> = divisor == 0 ? []
                    : modulus > 0 ? [0, 1 % modulus] : [0]
                #expect(targets.count == expectedSelections.count)
                #expect(Set(successors.map(\.selected)) == expectedSelections)
                let expectedFailure: NativeMachineEvaluationError? = divisor == 0 || modulus == 0
                    ? .divisionByZero : modulus < 0 ? .negativeModuloDivisor(modulus) : nil
                var expectedFailures: [NativeMachineEvaluationError] = []
                if divisor == 0 { expectedFailures.append(.divisionByZero) }
                if modulus < 0 { expectedFailures.append(.negativeModuloDivisor(modulus)) }
                else if modulus == 0 || divisor == 0 { expectedFailures.append(.divisionByZero) }
                #expect(failures == expectedFailures)
                let completeHistory = try #require(outcome.orderedActionFailureHistory)
                let recordedHistory = completeHistory.filter { $0.source == initialID }.map(\.failure)
                #expect(recordedHistory.map(\.reason) == failures)
                if divisor == 0 && modulus <= 0 {
                    #expect(recordedHistory.map(\.action) == [0, 0])
                    #expect(recordedHistory.map(\.branch) == [0, 1])
                    #expect(recordedHistory.map(\.site) == [1, 2])
                    #expect(recordedHistory.map(\.target) == [3, 2])
                    #expect(recordedHistory.map { $0.before.map(\.binding) } == [[0], []])
                    #expect(recordedHistory.map { $0.before.map(\.target) } == [[2], []])
                    #expect(recordedHistory.map { $0.before.map(\.value) } == [[0], []])
                }
                if let expectedFailure {
                    #expect(outcome.completion == .evaluationFailure(expectedFailure))
                } else {
                    #expect(outcome.completion == .exhausted)
                    #expect(completeHistory.isEmpty)
                }
            }
        }
        let rendered = try BranchwiseConjunctionFailureOrderModel.render()
        let proofInput = semanticFixture("BranchwiseConjunctionFailureOrderModel.tla")
        #expect(rendered.tlaBundle.root.tla == (try String(contentsOf: proofInput, encoding: .utf8)))
        let spec = BranchwiseConjunctionFailureOrderModel.spec
        let (authored, schedules) = try spec.compileRetainingAtomicBranchContinuations()
        let step = try #require(spec.sourceAtomicSteps.first)
        _ = try #require(schedules[step.model.label.name])
        let loweredModel = try spec.loweredSourceModel()
        let lowered = try #require(loweredModel.actions.first { $0.name == step.model.label.name }).body
        guard case .or(.define(let selection, let selectedValue,
                                .define(let result, .divide(let dividend, let divisor), let writes)), let other) = lowered else {
            Issue.record("The real alternative did not retain its division continuation")
            return
        }
        let replacement = StateExpr.int(1)
        let divisorChanged: Bool = divisor != replacement
        try #require(divisorChanged)
        let changed = ActionExpr.or(
            .define(selection, selectedValue, .define(result, .divide(dividend, replacement), writes)), other)
        do {
            _ = try StraightLineAssignmentCheck.checkedAtomicBranchContinuations(
                step, lowered: changed, stateRoots: Set(loweredModel.variables.map(\.name)))
            Issue.record("A shared fallible continuation accepted a changed divisor in just one arm")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.pick.branchContinuations")
        }
        let scenario = try #require(BranchwiseConjunctionFailureOrderModel.validationScenarios().first {
            $0.name == "Selected"
        })
        let configured = try scenario.render()
        guard case .compiled(let identity, _, _) = configured.tlaBundle.provenance else {
            Issue.record("The selected render did not retain the native compiler's identity")
            return
        }
        #expect(identity == authored.identity)
        #expect(configured.tlaBundle.root.tla == rendered.tlaBundle.root.tla)
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

    @Test("A fallible With domain has no successor and retains its evaluation failure")
    func undefinedChoiceDomain() throws {
        let machines = try UndefinedChoiceDomainModel.initialMachines()
        #expect(machines.count == 2)
        let machine = try #require(machines.first { $0.state.divisor == 0 })
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.successors(for: .pick)
        }
        #expect(machine.state.divisor == 0 && machine.state.result == 0)
        let defined = try #require(machines.first { $0.state.divisor == 1 })
        let successor = try #require(defined.successors(for: .pick).first)
        #expect(successor.state.divisor == 1 && successor.state.result == 1)

        let rendered = try UndefinedChoiceDomainModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let declarations = rendered.tlaBundle.root.tla.split(separator: "\n")
        let action = try #require(declarations.first { $0.hasPrefix("pick ==") })
        let failure = try #require(declarations.first {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
        })
        #expect(action.contains("IF divisor # 0"))
        #expect(action.contains("ELSE FALSE"))
        #expect(failure.contains("~(divisor # 0)"))
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
        let witness = semanticFixture("EitherBranchDivisionFailureSwiftWitness.txt")
        let expected = try #require(Parser.parse(source: nativeWitnessSource(String(contentsOf: witness, encoding: .utf8)))
            .statements.first?.item.as(FunctionDeclSyntax.self))
        let actualTokens = update.tokens(viewMode: .sourceAccurate).map(\.text)
        #expect(actualTokens == expected.tokens(viewMode: .sourceAccurate).map(\.text))
        let writes = try emitter.actionFunctions(action).writes
        try verifyGeneratedActionWriteOutput(update, action: action.body,
            program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
        let rootPart = try #require(update.as(FunctionDeclSyntax.self)?.body?.statements.compactMap {
            $0.item.as(FunctionDeclSyntax.self)
        }.first { $0.name.text == "_actionPart0" })
        let rootSource = rootPart.description
        try #require(rootSource.components(separatedBy: "failures.append(failure)").count == 2)
        try #require(update.description.components(separatedBy: rootSource).count == 2)
        let lostFailureSource = update.description.replacingOccurrences(of: rootSource,
            with: rootSource.replacingOccurrences(of: "failures.append(failure)", with: ""))
        #expect(lostFailureSource != update.description)
        let lostFailure = try #require(Parser.parse(source: lostFailureSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(lostFailure, action: action.body,
                program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("The generated action dropped a reached model failure")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.failures.0")
        }
        let classification = " where failure.isModelEvaluationFailure"
        try #require(rootSource.components(separatedBy: classification).count == 2)
        let uncheckedSource = update.description.replacingOccurrences(of: rootSource,
            with: rootSource.replacingOccurrences(of: classification, with: ""))
        try #require(uncheckedSource != update.description)
        let unchecked = try #require(Parser.parse(source: uncheckedSource)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(unchecked, action: action.body,
                program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("The generated action classified execution limits as model failures")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.failures.0")
        }
        let reversedOrder = update.description.replacingOccurrences(
            of: "visitAlternatives([false, true]", with: "visitAlternatives([true, false]")
        #expect(reversedOrder != update.description)
        let reversedVisitor = try #require(Parser.parse(source: reversedOrder)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(reversedVisitor, action: action.body,
                program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("The generated alternative order changed the first-failure rule")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.alternative.0")
        }

        let extraBranch = update.description.replacingOccurrences(
            of: "try _actionPart0(_Updates(), emit)",
            with: "try _actionPart0(_Updates(), emit)\ntry _actionPart1(_Updates(), emit)")
        #expect(extraBranch != update.description)
        let extraVisitor = try #require(Parser.parse(source: extraBranch)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(extraVisitor, action: action.body,
                program: compiled.program, stateFields: emitter.stateMemberNames, parts: writes)
            Issue.record("The generated visitor accepted an extra successful branch")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native.action.entry")
        }

        let droppedSuccessfulBranch = Parser.parse(source: update.description.replacingOccurrences(
            of: "try _actionPart1(updates, branchEmit)", with: "return"))
        let mutant = try #require(droppedSuccessfulBranch.statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(mutant.tokens(viewMode: .sourceAccurate).map(\.text) != actualTokens)
    }
}
