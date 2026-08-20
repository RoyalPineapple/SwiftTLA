import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

@TLAModel
private struct SanitizedActionLabelModel {
    static var spec: TLASpec {
        #spec("SanitizedActionLabelModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("procedure.work.enter") { value.becomes(1) }
            Action("procedure_work_enter") { value.becomes(2) }
            Action("step-2") { value.becomes(3) }
        }
    }
}

// MARK: - Minimal spec: counter with no invariants

@TLAModel
struct CounterNoInvs {
    static var spec: TLASpec {
        TLASpec("CounterNoInvs") {
            let x = Var<Int>("x")
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 3) }
            Action("dec") { x.becomes(x - 1).when(x > 0) }
        }
    }
}

@TLAModel
struct GeneratedAlgorithmCounter {
    enum Node: String, FiniteDomainKey {
        case left
        case right

        static let formalDomain: [Node] = [.left, .right]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.generated-algorithm-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedAlgorithmCounter") {
            Algorithm("GeneratedAlgorithmCounter") {
                let count = SharedVar(initial: 0)
                Each(Node.all, fairness: .weak) { _ in
                    While("increment", count < 2) {
                        When(count < 2)
                        Assert(count >= 0)
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
    }
}

struct GeneratedAlgorithmMachineTests {
    @Test("formal action labels retain raw names behind collision-safe Swift cases")
    func sanitizesGeneratedActionLabels() {
        let dotted = SanitizedActionLabelModel.ActionLabel.procedure_work_enter
        let underscored = SanitizedActionLabelModel.ActionLabel.procedure_work_enter_2
        let dashed = SanitizedActionLabelModel.ActionLabel.step_2
        #expect(dotted.toInvocation() == .init(name: "procedure.work.enter"))
        #expect(underscored.toInvocation() == .init(name: "procedure_work_enter"))
        #expect(dashed.toInvocation() == .init(name: "step-2"))
        #expect(SanitizedActionLabelModel.ActionLabel(invocation: dotted.toInvocation()) == dotted)
        #expect(SanitizedActionLabelModel.ActionLabel(invocation: underscored.toInvocation()) == underscored)
        #expect(SanitizedActionLabelModel.ActionLabel(invocation: dashed.toInvocation()) == dashed)
    }

    @Test("a bounded Algorithm generates the ordinary typed state machine")
    func generatedAlgorithmUsesTheSharedLowering() throws {
        var model = try GeneratedAlgorithmCounter.makeMachine()
        #expect(model.state.count == 0)
        let left = GeneratedAlgorithmCounter.ActionLabel.increment(process: .left)
        let result = try model.apply(left)
        #expect(result.before.count == 0)
        #expect(result.after.count == 1)
        #expect(model.state.count == 1)
        #expect(result.after.pc == .function([
            .string("left"): .string("increment"),
            .string("right"): .string("increment")
        ]))
    }
}

@TLAModel
struct GeneratedRestrictedProcessDomain {
    enum Member: Int, FiniteDomainKey {
        case worker = 1
        /// A value that is valid in state, but not a member of the process
        /// domain. This is the usual shape for an optional parent pointer.
        case none = 0

        static let formalDomain: [Member] = [.worker]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.restricted-process-member")

        var tlaValue: TLAValue { .int(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedRestrictedProcessDomain") {
            Algorithm("GeneratedRestrictedProcessDomain") {
                let count = SharedVar(initial: 0)
                Each(Member.all) { _ in
                    Do("increment") {
                        Assign(count, to: count + 1)
                    }
                }
            }
        }
    }
}

struct GeneratedRestrictedProcessDomainTests {
    @Test("the parser preserves an explicitly restricted FiniteDomainKey domain")
    func generatedModelUsesOnlyDeclaredProcessMembers() {
        GeneratedRestrictedProcessDomain._checkParserTree()
        #expect(GeneratedRestrictedProcessDomain.spec.actions.first?.bindings == [
            ActionBinding(name: "process", values: [.int(1)])
        ])
    }
}

@TLAModel
struct GeneratedSequentialCounter {
    static var spec: TLASpec {
        #spec("GeneratedSequentialCounter") {
            Algorithm("GeneratedSequentialCounter") {
                let count = SharedVar(initial: 0)
                Do("increment") {
                    Let(count + 1) { nextCount in
                        Assign(count, to: nextCount.expr)
                    }
                }
                Do("finish") {
                    Stop()
                }
            }
        }
    }
}

struct GeneratedSequentialMachineTests {
    @Test("a begin-style Algorithm generates scalar control state")
    func generatedSequentialAlgorithmPreservesScalarPC() throws {
        GeneratedSequentialCounter._checkParserTree()

        var model = try GeneratedSequentialCounter.makeMachine()
        let result = try model.apply(.increment)
        #expect(result.after.count == 1)
        #expect(result.after.pc == "finish")
    }
}

@TLAModel
struct GeneratedSimultaneousSwap {
    static var spec: TLASpec {
        #spec("GeneratedSimultaneousSwap") {
            Algorithm("GeneratedSimultaneousSwap") {
                let left = SharedVar(initial: 1)
                let right = SharedVar(initial: 2)
                Do("swap") {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            }
        }
    }
}

struct GeneratedSimultaneousSwapTests {
    @Test("generated updates read one old state and commit together")
    func generatedMachineSwapsValues() throws {
        var model = GeneratedSimultaneousSwap()

        let result = try model.apply(.swap)

        #expect(result.before.left == 1)
        #expect(result.before.right == 2)
        #expect(result.after.left == 2)
        #expect(result.after.right == 1)
        #expect(model.state == result.after)
    }

}

@TLAModel
struct GeneratedPairPattern {
    static var spec: TLASpec {
        #spec("GeneratedPairPattern") {
            Algorithm("GeneratedPairPattern") {
                let selected = SharedVar(initial: 0)
                Do("choose") {
                    With(SetExpr<Pair<Int, Bool>>.literal(
                        Pair(first: 1, second: true),
                        Pair(first: 2, second: false)
                    )) { number, flag in
                        Assert((number.expr == 1) || !flag.expr)
                        Assign(selected, to: number.expr)
                    }
                }
            }
        }
    }
}

struct GeneratedPairPatternTests {
    @Test("a generated model preserves tuple-pattern selection")
    func generatedMachineAppliesPairPatternBindings() throws {
        GeneratedPairPattern._checkParserTree()

        var model = GeneratedPairPattern()
        let result = try model.apply(.choose)

        #expect([1, 2].contains(result.after.selected))
    }
}

@TLAModel
struct GeneratedRangeInitializedAlgorithm {
    enum Node: String, FiniteDomainKey {
        case clock

        static let formalDomain: [Node] = [.clock]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.range-initialized-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedRangeInitializedAlgorithm") {
            Algorithm("GeneratedRangeInitializedAlgorithm") {
                let hour = SharedVar(in: 1...3)
                Each(Node.all) { _ in
                    Do("advance") {
                        When(hour < 3)
                        Assign(hour, to: hour + 1)
                    }
                }
            }
        }
    }
}

struct GeneratedRangeInitializedAlgorithmTests {
    @Test("#spec independently parses a finite SharedVar initial range")
    func generatedRangePreservesEveryInitialHour() {
        let initialHours = try computeInitialStates(GeneratedRangeInitializedAlgorithm.spec)
            .compactMap { $0["hour"] }

        #expect(Set(initialHours) == [.int(1), .int(2), .int(3)])
        #expect(GeneratedRangeInitializedAlgorithm.spec.variables.first { $0.name == "hour" }?.initialSet
            == .setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))]))
    }
}

@TLAModel
struct GeneratedIntegerChoiceAlgorithm {
    enum Node: String, FiniteDomainKey {
        case only

        static let formalDomain: [Node] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.generated-integer-choice-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedIntegerChoice") {
            Algorithm("GeneratedIntegerChoice") {
                let selected = SharedVar(initial: 0)
                Each(Node.all) { _ in
                    Do("choose") {
                        Choose(1...3) { choice in
                            Assign(selected, to: choice.expr)
                        }
                    }
                }
            }
        }
    }
}

struct GeneratedIntegerChoiceAlgorithmTests {
    @Test("#spec retains a bounded integer choice")
    func generatedModelRetainsIntegerChoice() throws {
        GeneratedIntegerChoiceAlgorithm._checkParserTree()
        let spec = GeneratedIntegerChoiceAlgorithm.spec
        let graph = try ModelChecker(spec: spec).exploreGraph()
        #expect(Set(graph.states.values.compactMap { $0.formalValues["selected"] }) == [.int(0), .int(1), .int(2), .int(3)])
    }
}

@TLAModel
struct GeneratedAlgorithmStateConstraint {
    static var spec: TLASpec {
        #spec("GeneratedAlgorithmStateConstraint") {
            Algorithm("GeneratedAlgorithmStateConstraint") {
                let count = SharedVar(initial: 0)
                Do("advance") {
                    Assign(count, to: count + 1)
                }
                StateConstraint(count < 2)
            }
        }
    }
}

struct GeneratedAlgorithmStateConstraintTests {
    @Test("#spec preserves an algorithm-local state constraint through both construction paths")
    func generatedModelPreservesStateConstraint() throws {
        GeneratedAlgorithmStateConstraint._checkParserTree()
        #expect(GeneratedAlgorithmStateConstraint.spec.constraint
            == .lessThan(.variable("count"), .value(.int(2))))
        let graph = try ModelChecker(spec: GeneratedAlgorithmStateConstraint.spec).exploreGraph()
        #expect(Set(graph.states.values.compactMap { $0.formalValues["count"] }) == [.int(0), .int(1)])
    }
}

@TLAModel
struct GeneratedProcessLocalInvariant {
    enum Node: String, FiniteDomainKey {
        case left
        case right

        static let formalDomain: [Node] = [.left, .right]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.process-local-invariant-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Label: String, PlusCalLabel {
        case receive
    }

    static var spec: TLASpec {
        #spec("GeneratedProcessLocalInvariant") {
            Algorithm("GeneratedProcessLocalInvariant") {
                Each(Node.all) { selfID in
                    let count = LocalVar(initial: 0)
                    Do(Label.receive) {
                        Skip()
                    }
                    Invariant("LocalCount") { count == 0 }
                    Invariant("ControlLocation") {
                        At(Label.receive, selfID) || Finished(selfID)
                    }
                }
            }
        }
    }
}

struct GeneratedProcessLocalInvariantTests {
    @Test("#spec preserves a process-local invariant through both construction paths")
    func generatedModelPreservesProcessLocalInvariant() {
        GeneratedProcessLocalInvariant._checkParserTree()
        #expect(GeneratedProcessLocalInvariant.spec.invariants.map(\.name) == ["LocalCount", "ControlLocation"])
        #expect(GeneratedProcessLocalInvariant.spec.invariants[0].body == .forAll(
            .setLiteral([.value(.string("left")), .value(.string("right"))]),
            "process",
            .equal(
                .functionApply(.variable("count"), .variable("process")),
                .value(.int(0))
            )
        ))
    }
}

@TLAModel
struct GeneratedDependentInitialAlgorithm {
    enum Node: String, FiniteDomainKey {
        case left
        case right

        static let formalDomain: [Node] = [.left, .right]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.dependent-initial-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Phase: String, TLAValueType {
        case active
        case inactive
    }

    static var spec: TLASpec {
        #spec("GeneratedDependentInitialAlgorithm") {
            Algorithm("GeneratedDependentInitialAlgorithm") {
                let seed = SharedVar(in: SetExpr<Bool>.literal(false, true))
                let mirrors = SharedVar(initial: Function<Node, Phase>.mapping { node in
                    If(node == .left && seed == true, then: .active, else: .inactive)
                })
                Each(Node.all) { _ in
                    Do("stop") {
                        Assign(mirrors, to: mirrors)
                        Stop()
                    }
                }
            }
        }
    }
}

struct GeneratedDependentInitialAlgorithmTests {
    @Test("#spec independently preserves a dependent typed function initializer")
    func generatedModelPreservesDependentInitialStates() {
        let states = try computeInitialStates(GeneratedDependentInitialAlgorithm.spec)

        #expect(Set(states.compactMap { $0["mirrors"] }) == [
            .function([.string("left"): .string("inactive"), .string("right"): .string("inactive")]),
            .function([.string("left"): .string("active"), .string("right"): .string("inactive")])
        ])
    }
}

struct NestedAdapterConcurrencyTests {
    @Test("Nested adapters observe and execute through their canonical model")
    @MainActor
    func nestedAdaptersShareCanonicalObservation() async throws {
        let invocation = TLAActionInvocation(name: "advance")
        let modelVariable: NestedComposedCounter.Variables = .count
        let observableVariable: NestedComposedCounter.Observable.Variables = .count
        let actorVariable: NestedComposedCounter.Actor.Variables = .count
        let observableLabel: NestedComposedCounter.Observable.ActionLabel = .advance
        let actorLabel: NestedComposedCounter.Actor.ActionLabel = .advance
        var model = try NestedComposedCounter.makeMachine()
        let observable = NestedComposedCounter.Observable()
        let actor = NestedComposedCounter.Actor()
        let callbackRecorder = NestedCallbackRecorder()
        observable.onAdvance = { before, after in
            await callbackRecorder.record(before: before, after: after)
        }

        let expectedBefore = await model.machineObservation()
        #expect(modelVariable == .count)
        #expect(observableVariable == .count)
        #expect(actorVariable == .count)
        #expect(observableLabel.toInvocation() == invocation)
        #expect(actorLabel.toInvocation() == invocation)
        #expect(await observable.machineObservation() == expectedBefore)
        #expect(await actor.machineObservation() == expectedBefore)

        let expected = try await model.execute(invocation)
        let observed = try await observable.execute(invocation)
        let acted = try await actor.execute(invocation)

        #expect(observed.before == expected.before)
        #expect(observed.after == expected.after)
        #expect(acted.before == expected.before)
        #expect(acted.after == expected.after)
        let count = TLAStateProjection.Token(validating: "count")!
        #expect(await observable.machineObservation().state.projection?.value(for: count) == .int(1))
        #expect(await actor.machineObservation().state.projection?.value(for: count) == .int(1))
        #expect(observable.state.count == 1)
        #expect(await actor.state.count == 1)
        #expect(await callbackRecorder.transitions.count == 1)
        #expect(await callbackRecorder.transitions.first?.0 == expected.before)
        #expect(await callbackRecorder.transitions.first?.1 == expected.after)
    }

    @Test("Nested actor commits overlapping executions without stale write-back")
    func nestedActorExecutesOverlappingTransitionsAtomically() async throws {
        let actor = NestedComposedCounter.Actor()
        let invocation = TLAActionInvocation(name: "advance")

        async let first = actor.execute(invocation)
        async let second = actor.execute(invocation)
        _ = try await (first, second)

        let count = TLAStateProjection.Token(validating: "count")!
        #expect(await actor.machineObservation().state.projection?.value(for: count) == .int(2))
    }

    @Test("Nested observable rejects disabled execution without notification")
    @MainActor
    func nestedObservableSuppressesCallbackAfterFailedExecution() async throws {
        let observable = NestedComposedCounter.Observable()
        let recorder = NestedCallbackRecorder()
        let invocation = TLAActionInvocation(name: "advance")
        observable.onAdvance = { before, after in
            await recorder.record(before: before, after: after)
        }

        _ = try await observable.execute(invocation)
        _ = try await observable.execute(invocation)
        let beforeFailure = await observable.machineObservation()
        await #expect(throws: GeneratedMachineError.self) {
            try await observable.execute(invocation)
        }

        #expect(await observable.machineObservation() == beforeFailure)
        #expect(await recorder.transitions.count == 2)
    }
}

// MARK: - HourClock spec with invariants

@TLAModel
struct HourClock {
    static var spec: TLASpec {
        TLASpec("HourClock") {
            let hr = Var<Int>("hr")
            Variable(hr, 1)
            Action("Tick") { hr.becomes(hr + 1).when(hr < 12) }
            Action("Reset") { (hr == 12) && hr.becomes(1) }
            Invariant("TypeOK") { hr >= 1 && hr <= 12 }
        }
    }
}

// MARK: - Counter with explicit invariant

@TLAModel
struct CounterWithInv {
    static var spec: TLASpec {
        TLASpec("CounterWithInv") {
            let x = Var<Int>("x")
            Variable(x, 0)
            Action("inc") { x.becomes(x + 1).when(x < 5) }
            Invariant("nonNeg") { x >= 0 }
        }
    }
}

// MARK: - Multi-variable spec with invariant

@TLAModel
struct MultiVar {
    static var spec: TLASpec {
        TLASpec("MultiVar") {
            let a = Var<Int>("a")
            let b = Var<Int>("b")
            Variable(a, 0)
            Variable(b, 0)
            Action("incA") { a.becomes(a + 1).when(a < 2) }
            Action("incB") { b.becomes(b + 1).when(b < 2) }
            Invariant("sumLE4") { (a + b) <= 4 }
        }
    }
}

// MARK: - Builder-only: Var initial in constructor, no explicit Variable()

@TLAModel
struct BuilderOnlyClock {
    static var spec: TLASpec {
        TLASpec("BuilderOnlyClock") {
            let hr = Var<Int>("hr", 1)
            hr
            Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
            Invariant("valid") { hr >= 1 && hr <= 12 }
        }
    }
}

@TLAModel
struct TwoCarElevatorMachine {
    static var spec: TLASpec {
        TLASpec("TwoCarElevatorMachine") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            Action("moveElevator", parameters: [ActionParameter("id", values: [1, 2])]) {
                floor.becomes(1)
            }
        }
    }

    @TLAObservable
    final class Observable {}
}

@TLAModel
struct ThreeParameterActionMachine {
    static var spec: TLASpec {
        TLASpec("ThreeParameterActionMachine") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            Action("board", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(1)
            }
        }
    }

    @TLAObservable
    final class Observable {}

    @TLAActor
    actor Actor {}
}

@TLAModel
struct EndToEndThreeParameterActionMachine {
    static var spec: TLASpec {
        TLASpec("EndToEndThreeParameterActionMachine") {
            let floor = Var<Int>("floor")
            let person = Expr<Int>(.variable("person"))
            let elevator = Expr<Int>(.variable("elevator"))
            let direction = Expr<Int>(.variable("direction"))
            Variable(floor, 0)
            Action("board", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(person + elevator + direction)
            }
        }
    }
}

@TLAModel
struct NondeterministicConstrainedMachine {
    static var spec: TLASpec {
        TLASpec("NondeterministicConstrainedMachine") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("choose") {
                choose(value, from: StateExpr.set([1, 2, 3]))
            }
            Constraint(value <= 2)
            Invariant("WithinBound") { value <= 3 }
        }
    }
}

@TLAModel
struct NestedComposedCounter {
    static var spec: TLASpec {
        TLASpec("NestedComposedCounter") {
            let count = Var<Int>("count")
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 2) }
        }
    }

    @TLAObservable
    final class Observable {}

    @TLAActor
    actor Actor {}
}

private actor NestedCallbackRecorder {
    private(set) var transitions: [(NestedComposedCounter.State, NestedComposedCounter.State)] = []

    func record(before: NestedComposedCounter.State, after: NestedComposedCounter.State) {
        transitions.append((before, after))
    }
}

// MARK: - Tests for generated verification methods

struct GeneratedStateMachineTests {
    @Test("#spec preserves the constrained TLASpec builder for model generation")
    func specExpressionMacroCompilesExternally() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/SpecExpressionMacro")
        let result = try runSwift(["run", "--package-path", fixture.path])

        #expect(result.status == 0, Comment(rawValue: result.output))
    }

    private struct BoardCallback: Sendable {
        let person: Int
        let elevator: Int
        let direction: Int
        let before: ThreeParameterActionMachine.State
        let after: ThreeParameterActionMachine.State
    }

    @Test("Observable parameterized action applies its selected finite-domain argument")
    @MainActor
    func observableParameterizedAction() async throws {
        let elevator = TwoCarElevatorMachine.Observable()
        let callbackID = LockedValue<Int?>(nil)
        elevator.onMoveElevator = { id, _, _ in callbackID.value = id }
        _ = try await elevator._moveElevator(id: 2)
        #expect(elevator.state.floor == 1)
        #expect(callbackID.value == 2)
    }

    @Test("Model macro generates a parameterized action method")
    func modelParameterizedAction() throws {
        var elevator = try TwoCarElevatorMachine.makeMachine()
        _ = try elevator.applymoveElevator(id: 1)
        #expect(elevator.floor == 1)
    }

    @Test("Model macro forwards every list parameter to the runtime invocation")
    func modelMacroForwardsEveryVariadicParameter() throws {
        var enabled = try ThreeParameterActionMachine.makeMachine()
        _ = try enabled.applyboard(person: 2, elevator: 20, direction: 200)
        #expect(enabled.floor == 1)
        #expect(ThreeParameterActionMachine.spec.actions[0].bindings.map(\.name) == [
            "person", "elevator", "direction"
        ])

        var invalidMiddleParameter = try ThreeParameterActionMachine.makeMachine()
        let before = invalidMiddleParameter.tlaSnapshot()
        #expect(throws: GeneratedMachineError.self) {
            try invalidMiddleParameter.apply(.board(person: 2, elevator: 30, direction: 200))
        }
        #expect(invalidMiddleParameter.floor == 0)
        #expect(invalidMiddleParameter.tlaSnapshot() == before)
    }

    @Test("Three-parameter actions preserve one ordered contract across builder, parser, macro, runtime, and export")
    func threeParameterActionIsConsistentAcrossEveryExecutionPath() throws {
        let source = """
        {
            Action("board", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(person + elevator + direction)
            }
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(closure)
        let floor = Var<Int>("floor")
        let person = Expr<Int>(.variable("person"))
        let elevator = Expr<Int>(.variable("elevator"))
        let direction = Expr<Int>(.variable("direction"))
        let builder = TLASpec("EndToEndThreeParameterActionMachine") {
            Variable(floor, 0)
            Action("board", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(person + elevator + direction)
            }
        }

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.actions.count == 1)
        #expect(parsed.actions[0].name == builder.actions[0].name)
        #expect(parsed.actions[0].body == builder.actions[0].body)
        #expect(parsed.actions[0].bindings == builder.actions[0].bindings)
        #expect(EndToEndThreeParameterActionMachine.spec.actions == builder.actions)

        let expectedArguments: [[TLAValue]] = [
            [.int(1), .int(10), .int(100)], [.int(1), .int(10), .int(200)],
            [.int(1), .int(20), .int(100)], [.int(1), .int(20), .int(200)],
            [.int(2), .int(10), .int(100)], [.int(2), .int(10), .int(200)],
            [.int(2), .int(20), .int(100)], [.int(2), .int(20), .int(200)]
        ]
        let graph = try ModelChecker(spec: builder).exploreGraph()
        #expect(graph.transitions[.init(0)]?.map(\.label.arguments) == expectedArguments)

        let generatedMatrix = try EndToEndThreeParameterActionMachine.transitionMatrix()
        let initialInvocations = generatedMatrix
            .filter { $0.from.floor == 0 }
            .map(\.invocation.arguments)
        #expect(initialInvocations == expectedArguments)

        let wrappers = try builder.compile().renderedTLAModuleBundle().tla.split(separator: "\n").filter { $0.hasPrefix("board__") }
        #expect(wrappers == [
            "board__0_0_0 == board(1, 10, 100)",
            "board__0_0_1 == board(1, 10, 200)",
            "board__0_1_0 == board(1, 20, 100)",
            "board__0_1_1 == board(1, 20, 200)",
            "board__1_0_0 == board(2, 10, 100)",
            "board__1_0_1 == board(2, 10, 200)",
            "board__1_1_0 == board(2, 20, 100)",
            "board__1_1_1 == board(2, 20, 200)"
        ])

        let runtime = try SpecRuntime(spec: builder)
        let initial = try #require(runtime.initialStateProjections().first)
        let invocation = TLAActionInvocation(
            name: "board", arguments: [.int(2), .int(20), .int(200)])
        let floor = try #require(TLAStateProjection.Token(validating: "floor"))
        let successor = try #require(try runtime.successors(invocation, from: initial).first)
        #expect(successor.value(for: floor) == .int(222))
        #expect(throws: SpecRuntime.RuntimeError.self) {
            try runtime.successors(.init(name: "board", arguments: [.int(2), .int(30), .int(200)]), from: initial)
        }
        #expect(initial.value(for: floor) == .int(0))

        var machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let before = machine.tlaSnapshot()
        let evidence = try machine.apply(.board(person: 2, elevator: 20, direction: 200))
        #expect(evidence.action.toInvocation() == invocation)
        #expect(evidence.after.floor == 222)
        #expect(throws: GeneratedMachineError.self) {
            try machine.apply(.board(person: 2, elevator: 30, direction: 200))
        }
        let floorToken = TLAStateProjection.Token(validating: "floor")!
        #expect(machine.tlaSnapshot().projection?.value(for: floorToken) == .int(222))
        #expect(before.projection?.value(for: floorToken) == .int(0))
    }

    @Test("Canonical generated machine preserves typed labels, evidence, and failed snapshots")
    func canonicalGeneratedMachineUsesCheckedThreeArgumentInvocations() throws {
        var machine = try ThreeParameterActionMachine.makeMachine()
        let label = ThreeParameterActionMachine.ActionLabel.board(person: 2, elevator: 20, direction: 200)
        let evidence = try machine.apply(label)

        #expect(evidence.action == label)
        #expect(evidence.action.toInvocation() == .init(name: "board", arguments: [.int(2), .int(20), .int(200)]))
        #expect(evidence.before.floor == 0)
        #expect(evidence.after.floor == 1)

        let before = machine.tlaSnapshot()
        #expect(throws: GeneratedMachineError.self) {
            try machine.apply(.board(person: 2, elevator: 30, direction: 200))
        }
        #expect(machine.tlaSnapshot() == before)
    }

    @Test("Canonical generated execution preserves the complete parameterized invocation")
    func canonicalGeneratedExecutionPreservesParameterizedInvocationEvidence() async throws {
        var machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let invocation = TLAActionInvocation(
            name: "board",
            arguments: [.int(2), .int(20), .int(200)]
        )
        let before = await machine.machineObservation()

        let evidence = try await machine.execute(invocation)
        let after = await machine.machineObservation()

        #expect(evidence.action == .board(person: 2, elevator: 20, direction: 200))
        #expect(evidence.before.floor == 0)
        #expect(evidence.after.floor == 222)
        let floor = TLAStateProjection.Token(validating: "floor")!
        #expect(before.state.projection?.value(for: floor) == .int(0))
        #expect(after.state.projection?.value(for: floor) == .int(222))
    }

    @Test("Generated verification retains every constrained nondeterministic successor")
    func generatedVerificationRetainsNondeterministicSuccessors() throws {
        let invocation = TLAActionInvocation(name: "choose")
        let matrixSuccessors = try NondeterministicConstrainedMachine.transitionMatrix()
            .filter { $0.from == .init(value: 0) && $0.invocation == invocation }
            .map(\.to)

        #expect(matrixSuccessors.count == 2)
        #expect(matrixSuccessors.contains(.init(value: 1)))
        #expect(matrixSuccessors.contains(.init(value: 2)))
        #expect(!matrixSuccessors.contains(.init(value: 3)))
        try NondeterministicConstrainedMachine.verifyTransitions()
        try NondeterministicConstrainedMachine.verifyInvariants()
    }

    @Test("Observable and actor adapters return the canonical three-argument transition evidence")
    @MainActor
    func observableAndActorMatchCanonicalThreeArgumentEvidence() async throws {
        var model = try ThreeParameterActionMachine.makeMachine()
        let expected = try model.apply(.board(person: 2, elevator: 20, direction: 200))

        let observable = ThreeParameterActionMachine.Observable()
        let callback = LockedValue<BoardCallback?>(nil)
        observable.onBoard = { person, elevator, direction, before, after in
            callback.value = .init(
                person: person,
                elevator: elevator,
                direction: direction,
                before: before,
                after: after
            )
        }
        let observed = try await observable._board(person: 2, elevator: 20, direction: 200)

        let actor = ThreeParameterActionMachine.Actor()
        let acted = try await actor.execute(
            ThreeParameterActionMachine.ActionLabel.board(person: 2, elevator: 20, direction: 200).toInvocation()
        )

        #expect(observed.action.toInvocation() == expected.action.toInvocation())
        #expect(observed.before.floor == expected.before.floor)
        #expect(observed.after.floor == expected.after.floor)
        #expect(acted.action.toInvocation() == expected.action.toInvocation())
        #expect(acted.before.floor == expected.before.floor)
        #expect(acted.after.floor == expected.after.floor)
        #expect(callback.value?.person == 2)
        #expect(callback.value?.elevator == 20)
        #expect(callback.value?.direction == 200)
        #expect(callback.value?.before.floor == expected.before.floor)
        #expect(callback.value?.after.floor == expected.after.floor)
    }

    @Test("Rejected generated labels preserve model, observable, and actor state")
    @MainActor
    func rejectedActionsDoNotMutateOrNotify() async throws {
        let expectedInvocation = TLAActionInvocation(
            name: "board",
            arguments: [.int(2), .int(30), .int(200)]
        )

        var model = try ThreeParameterActionMachine.makeMachine()
        let modelBefore = model.tlaSnapshot()
        do {
            _ = try model.apply(.board(person: 2, elevator: 30, direction: 200))
            Issue.record("Expected rejected model action")
        } catch {
            assertRejectedBoardError(error, expectedInvocation: expectedInvocation)
        }
        #expect(model.tlaSnapshot() == modelBefore)

        let observable = ThreeParameterActionMachine.Observable()
        let callbackCount = LockedValue(0)
        observable.onBoard = { _, _, _, _, _ in callbackCount.value += 1 }
        let observableBefore = observable.tlaSnapshot()
        do {
            _ = try await observable._board(person: 2, elevator: 30, direction: 200)
            Issue.record("Expected rejected observable action")
        } catch {
            assertRejectedBoardError(error, expectedInvocation: expectedInvocation)
        }
        #expect(observable.tlaSnapshot() == observableBefore)
        #expect(callbackCount.value == 0)

        let actor = ThreeParameterActionMachine.Actor()
        let actorBefore = await actor.tlaSnapshot()
        do {
            _ = try await actor.execute(
                ThreeParameterActionMachine.ActionLabel.board(person: 2, elevator: 30, direction: 200).toInvocation()
            )
            Issue.record("Expected rejected actor action")
        } catch {
            assertRejectedBoardError(error, expectedInvocation: expectedInvocation)
        }
        #expect(await actor.tlaSnapshot() == actorBefore)
    }

    @Test("Removed fixed-arity action syntax does not type check")
    func legacyParameterizedActionSyntaxIsUnavailable() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidActionParameterAPI")
        let result = try runSwift(["build", "--package-path", fixture.path])

        #expect(result.status != 0)
        #expect(result.output.contains("Parameterized action 'legacyParameter' requires a parameters list"))
        #expect(result.output.contains("Parameterized action 'legacyTwoParameters' requires a parameters list"))
        #expect(result.output.contains("Parameterized action 'legacyID' requires a parameters list"))
        #expect(result.output.contains("Parameterized action 'legacyPair' requires a parameters list"))
        #expect(result.output.contains("value of type 'NamedAction' has no member 'binding'"))
        #expect(result.output.contains("value of type 'ActionDecl' has no member 'binding'"))
        #expect(result.output.contains("incorrect argument label in call (have 'name:body:binding:', expected 'name:body:bindings:')"))
    }

    @Test("Builder path: TLASpec from Var with initial, no explicit Variable")
    func builderOnlyClockRuntime() throws {
        let spec = TLASpec("BuilderOnlyClock") {
            let hr = Var<Int>("hr", 1)
            hr
            Action("tick") { (hr < 12 && hr.becomes(hr + 1)) || (hr == 12 && hr.becomes(1)) }
            Invariant("valid") { hr >= 1 && hr <= 12 }
        }
        #expect(spec.variables.count == 1)
        #expect(spec.variables[0].name == "hr")
        #expect(spec.variables[0].initial == .int(1))
        let result = try ModelChecker(spec: spec, maxStates: 100).check()
        if case .ok(let count) = result { #expect(count == 12) } else {
            #expect(Bool(false), "Expected 12 states")
        }
    }

    @Test("verifySpec passes for CounterNoInvs")
    func counterNoInvsVerifySpec() throws {
        try CounterNoInvs.verifySpec()
    }

    private func runSwift(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftTLA-invalid-action-parameter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift"] + arguments + ["--scratch-path", scratch.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (
            process.terminationStatus,
            String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}
