import Foundation
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax

struct RandomSubsetExpressionTests {
    @Test("exhaustive initialization includes every possible random-subset member")
    func completeFiniteInitialSupport() throws {
        let states = try FiniteRandomSubsetInitialModel.initialMachines().map(\.state.chosen)
        #expect(Set(states) == Set([1, 2, 3]))
        #expect(states.count == 3)

        let compilation = try FiniteRandomSubsetInitialModel.spec.compile()
        let compiled = try Set(CompiledRuntime(compilation: compilation).initialStates().map {
            try renderedValue(named: "chosen", in: $0, compilation: compilation)
        })
        #expect(compiled == Set([.int(1), .int(2), .int(3)]))

        let tla = try FiniteRandomSubsetInitialModel.render().tlaBundle.tla
        #expect(tla.contains("chosen \\in {1, 2, 3}"))
        #expect(!tla.contains("chosen \\in RandomSubset("))
    }

    @Test("actual random-subset outputs reject a sampled or weakened exhaustive rule")
    func emittedInitialSupportIsChecked() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("RandomSubsetFixtures.swift")
        let source = Parser.parse(source: try String(contentsOf: fixture, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }.first { $0.name.text == "FiniteRandomSubsetInitialModel" })
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let initialIndex = try #require(members.firstIndex {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let initial = members[initialIndex]
        let chosen = try #require(model.program.layout.variables.first {
            $0.declaration.name == "chosen"
        })
        let name = emitter.variable(chosen.id)
        try verifyRandomSubsetInitialSupport(initial, expected: [(name, false)])
        let sampledOnly = initial.description.replacingOccurrences(
            of: "randomSubsetInitialSupport", with: "randomSubset")
        #expect(sampledOnly != initial.description)
        let altered = try #require(Parser.parse(source: sampledOnly).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyRandomSubsetInitialSupport(altered, expected: [(name, false)])
        }
        let lostFailure = initial.description.replacingOccurrences(
            of: "if firstFailure == nil", with: "if firstFailure != nil")
        #expect(lostFailure != initial.description)
        let lostFailureDeclaration = try #require(Parser.parse(source: lostFailure)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try emitter.verifyInitialStateAssembly(lostFailureDeclaration)
        }

        var construction = Array(members[initialIndex...(initialIndex + 6)])
        let sampled = construction[6].description
        let wrongMode = sampled.replacingOccurrences(
            of: "_sampleRandomSubset: true", with: "_sampleRandomSubset: false")
        #expect(wrongMode != sampled)
        construction[6] = try #require(Parser.parse(source: wrongMode).statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedInitialConstruction(construction, configured: false, sampled: true)
        }

        let tla = try FiniteRandomSubsetInitialModel.render().tlaBundle.tla
        let predicates = ["pc = \"stay\"", "(2 > 0 /\\ chosen \\in {1, 2, 3})"]
        try verifyRenderedInitialConjunction(tla, predicates: predicates)
        let weakened = tla.replacingOccurrences(of: "2 > 0", with: "2 = 0")
        #expect(weakened != tla)
        #expect(throws: CompilationDiagnostic.self) {
            try verifyRenderedInitialConjunction(weakened, predicates: predicates)
        }
    }

    @Test("finite random subsets contain distinct source members and cap at the domain size")
    func finiteDomain() throws {
        #expect(try _NativeMachineOperations.randomSubset(upTo: 2, from: Set([1, 2, 3])).count == 2)
        #expect(try _NativeMachineOperations.randomSubset(upTo: 5, from: Set([1, 2])) == Set([1, 2]))
        #expect(try _NativeMachineOperations.randomSubset(upTo: 0, from: Set([1])) == [])
        #expect(throws: NativeMachineEvaluationError.invalidRandomSubsetCount(-1)) {
            try _NativeMachineOperations.randomSubset(upTo: -1, from: Set([1]))
        }
    }

    @Test("explicit sampling covers large function domains without enumerating the function space")
    func generatedFunctionDomain() throws {
        let machines = try RandomSubsetFunctionModel.sampledInitialMachines()
        #expect(machines.count == 100)
        let functions = Set(machines.map(\.state.samples))
        #expect(functions.count == 100)
        for function in functions {
            #expect(Set(function.keys) == Set(1...30))
        }
        let replay = try RandomSubsetFunctionModel.makeMachine(machines[0].state)
        #expect(replay.state.samples == machines[0].state.samples)
    }

    @Test("large initial domains fail exhaustive enumeration instead of returning a sample")
    func largeDomainIsIncomplete() throws {
        let expected = ExplorationError.initialStateLimitExceeded(
            actualCount: 1 << 30, maximumCount: 1_000_000)
        #expect(throws: expected) { try RandomSubsetFunctionModel.initialMachines() }
        let compilation = try RandomSubsetFunctionModel.spec.compile()
        #expect(throws: expected) { try CompiledRuntime(compilation: compilation).initialStates() }
    }

    @Test("selected initialization accepts a valid function outside the latest random sample")
    func selectedFunctionOutsideSample() throws {
        let sampled = Set(try RandomSubsetFunctionModel.sampledInitialMachines().map(\.state.samples))
        let unsampled = (0...100).lazy.map { pattern in
            Dictionary(uniqueKeysWithValues: (1...30).map { key in
                (key, key <= 7 && pattern & (1 << (key - 1)) != 0)
            })
        }.first { !sampled.contains($0) }
        guard let unsampled else {
            Issue.record("101 distinct valid functions cannot all be in a 100-member sample")
            return
        }

        let selected = RandomSubsetFunctionModel.State(samples: unsampled)
        #expect(try RandomSubsetFunctionModel.makeMachine(selected).state == selected)
        var invalid = unsampled
        invalid[31] = false
        #expect(throws: GeneratedMachineError.invalidInitialState) {
            try RandomSubsetFunctionModel.makeMachine(.init(samples: invalid))
        }
    }

    @Test("selected random-subset initialization preserves zero and negative count outcomes")
    func selectedCountOutcomes() throws {
        #expect(throws: NativeMachineEvaluationError.invalidRandomSubsetCount(-1)) {
            try RandomSubsetCountModel.makeMachine(.init(limit: -1, chosen: 1))
        }
        #expect(throws: GeneratedMachineError.invalidInitialState) {
            try RandomSubsetCountModel.makeMachine(.init(limit: 0, chosen: 1))
        }
    }

    @Test("independent initial branches retain a valid state and the first evaluation failure")
    func mixedInitialOutcomes() throws {
        let outcome = try MixedInitialEvaluationModel.initialOutcomes()
        #expect(outcome.states.map(\.state) == [.init(limit: 1, chosen: 7)])
        #expect(outcome.firstFailure == .invalidRandomSubsetCount(-1))
        let compilation = try MixedInitialEvaluationModel.spec.compile()
        let compiled = try CompiledRuntime(compilation: compilation).initialOutcomes()
        #expect(compiled.states.count == 1)
        #expect(try renderedValue(named: "limit", in: compiled.states[0], compilation: compilation) == .int(1))
        #expect(try renderedValue(named: "chosen", in: compiled.states[0], compilation: compilation) == .int(7))
        #expect(compiled.firstFailure == outcome.firstFailure)
        #expect(throws: NativeMachineEvaluationError.invalidRandomSubsetCount(-1)) {
            try MixedInitialEvaluationModel.initialMachines()
        }
        #expect(throws: NativeMachineEvaluationError.invalidRandomSubsetCount(-1)) {
            try CompiledRuntime(compilation: compilation).initialStates()
        }
    }

    @Test("rendered initial states and negative-count failures match the source rule")
    func renderedMixedInitialOutcomes() throws {
        let tla = try MixedInitialEvaluationModel.render().tlaBundle.tla
        let predicates = ["pc = \"stay\"", "limit \\in {-1, 1}",
            "(limit > 0 /\\ chosen \\in {7})"]
        try verifyRenderedInitialConjunction(tla, predicates: predicates)
        let name = "__SwiftTLAInitialRandomSubsetCountFailure2("
        let expected = "__SwiftTLAInitialRandomSubsetCountFailure2(__SwiftTLAInitialFailedCount2) == "
            + "(LET __SwiftTLAInitialValue0 == \"stay\" IN (\\E __SwiftTLAInitialValue1 \\in {-1, 1}: "
            + "(__SwiftTLAInitialFailedCount2 < 0 /\\ "
            + "__SwiftTLAInitialFailedCount2 = __SwiftTLAInitialValue1)))"
        func emittedFailure(in module: String) -> String? {
            module.components(separatedBy: "\n").first { $0.hasPrefix(name) }
        }
        #expect(emittedFailure(in: tla) == expected)
        let altered = tla.replacingOccurrences(of: "__SwiftTLAInitialFailedCount2 < 0",
            with: "__SwiftTLAInitialFailedCount2 > 0")
        #expect(altered != tla)
        #expect(emittedFailure(in: altered) != expected)
        let weakened = tla.replacingOccurrences(of: "limit > 0", with: "limit < 0")
        #expect(throws: CompilationDiagnostic.self) {
            try verifyRenderedInitialConjunction(weakened, predicates: predicates)
        }
    }

    @Test("native checking explores valid initial branches while reporting their failed sibling")
    func mixedInitialValidation() throws {
        var observed: [MixedInitialEvaluationModel.State] = []
        let outcome = try MachineValidator.run(
            initialOutcomes: MixedInitialEvaluationModel.initialOutcomes(), maximumStates: 4,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false
        ) { event in
            if case .state(_, let snapshot, let initial, _, _) = event, initial {
                observed.append(snapshot.state)
            }
        }
        #expect(observed == [.init(limit: 1, chosen: 7)])
        #expect(outcome.initialStates == 1 && outcome.states >= 1)
        #expect(outcome.firstEvaluationFailure == .invalidRandomSubsetCount(-1))
        #expect(outcome.completion == .evaluationFailure(.invalidRandomSubsetCount(-1)))

        let scenario = try #require(MixedInitialEvaluationModel.validationScenarios().first)
        let configured = try scenario.runValidation(maximumStates: 4, checking: scenario.checking,
            stopOnViolation: false, stopOnReachability: false) { _ in }
        #expect(configured.initialStates == 1)
        #expect(configured.firstEvaluationFailure == .invalidRandomSubsetCount(-1))
        #expect(configured.completion == .evaluationFailure(.invalidRandomSubsetCount(-1)))

        let failedOnly = try RandomSubsetFailureOrderModel.initialOutcomes()
        #expect(failedOnly.states.isEmpty)
        let emptyOutcome = try MachineValidator.run(
            initialOutcomes: failedOnly, maximumStates: 4,
            checking: .init(properties: [], checkDeadlock: false), stopOnViolation: false
        ) { _ in
            Issue.record("A failed-only initializer emitted a graph event")
        }
        #expect(emptyOutcome.initialStates == 0 && emptyOutcome.states == 0)
        #expect(emptyOutcome.firstEvaluationFailure == .invalidRandomSubsetCount(-1))
        #expect(emptyOutcome.completion == .evaluationFailure(.invalidRandomSubsetCount(-1)))
    }

    @Test("invalid sample count fails before evaluating its domain")
    func countFailurePrecedesDomainFailure() throws {
        let expected = NativeMachineEvaluationError.invalidRandomSubsetCount(-1)
        #expect(throws: expected) { try RandomSubsetFailureOrderModel.initialMachines() }
        let compilation = try RandomSubsetFailureOrderModel.spec.compile()
        #expect(throws: expected) { try CompiledRuntime(compilation: compilation).initialStates() }
    }

    @Test("formal evaluation samples a large function space without enumerating it")
    func interpretedFunctionDomain() throws {
        let sample = RandomSubset(upTo: 100,
            from: Functions(from: IntRange(1, through: 64), to: SetExpr<Bool>.literal(false, true)))
        guard case .set(let functions) = try evaluateClosed(sample.stateExpr) else {
            Issue.record("RandomSubset did not return a set")
            return
        }
        #expect(functions.count == 100)
        for value in functions {
            guard case .function(let mapping) = value else {
                Issue.record("RandomSubset returned a non-function member")
                continue
            }
            #expect(Set(mapping.keys) == Set((1...64).map(TLAValue.int)))
            #expect(mapping.values.allSatisfy { $0 == .bool(false) || $0 == .bool(true) })
        }
    }
}
