import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

@TLAModel
private struct SanitizedActionModel {
    static var spec: TLASpec {
        #spec("SanitizedActionModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("procedure.work.enter") { value.becomes(1) }
            SwiftTLA.Action("procedure_work_enter") { value.becomes(2) }
            SwiftTLA.Action("step-2") { value.becomes(3) }
        }
    }
}

@TLAModel
private struct InvocationNamedActionModel {
    static var spec: TLASpec {
        #spec("InvocationNamedActionModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("toInvocation") { value.becomes(1) }
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
            SwiftTLA.Action("inc") { x.becomes(x + 1).when(x < 3) }
            SwiftTLA.Action("dec") { x.becomes(x - 1).when(x > 0) }
        }
    }
}

@TLAModel
struct GeneratedAlgorithmCounter {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        static var defaultValue: Self { .left }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedAlgorithmCounter") {
            Algorithm("GeneratedAlgorithmCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(Node.all, fairness: .weak) { _ in
                    While(TestControlLabel.increment, count < 2) {
                        When(count < 2)
                        Assert(count >= 0)
                        Assign(count, to: count + 1)
                    }
                }
            })
        }
    }
}

@TLAModel
private struct SeededCounterMachine {
    static var spec: TLASpec {
        #spec("SeededCounterMachine") {
            Algorithm("SeededCounterMachine", scoped: { scope in
                let value = scope.sharedVar("value", in: 0...2)

                While(TestControlLabel.advance, true) {
                    Either {
                        When(value < 2)
                        Assign(value, to: value + 1)
                    } or: {
                        When(value == 2)
                        Assign(value, to: 0)
                    }
                }
            })
        }
    }
}

struct GeneratedAlgorithmMachineTests {
    @Test("generated actions retain collision-safe Swift cases")
    func sanitizesGeneratedActions() {
        let dotted = SanitizedActionModel.Action.procedure_work_enter
        let underscored = SanitizedActionModel.Action.procedure_work_enter_2
        let dashed = SanitizedActionModel.Action.step_2
        #expect((dotted == underscored) == false)
        #expect((underscored == dashed) == false)
        #expect((dashed == dotted) == false)
    }

    @Test("generated actions accept a case named toInvocation")
    func permitsCurrentActionNames() {
        #expect(InvocationNamedActionModel.Action.toInvocation == .toInvocation)
    }

    @Test("a bounded Algorithm generates the ordinary typed state machine")
    func generatedAlgorithmUsesTheSharedLowering() throws {
        var machine = try GeneratedAlgorithmCounter.makeMachine()
        #expect(machine.state.count == 0)
        let action = GeneratedAlgorithmCounter.Action.increment(process: .left)
        let result = try machine.send(action)
        #expect(result.before.count == 0)
        #expect(result.after.count == 1)
        #expect(machine.state.count == 1)
    }

    @Test("a generated machine accepts one declared initial state")
    func generatedMachineAcceptsDeclaredInitialState() throws {
        var machine = try SeededCounterMachine.makeMachine(.init(value: 2))

        #expect(machine.state.value == 2)
        #expect(try machine.send(.advance).after.value == 0)
    }

    @Test("a generated machine rejects an initial state outside Init")
    func generatedMachineRejectsUndeclaredInitialState() {
        do {
            _ = try SeededCounterMachine.makeMachine(.init(value: 3))
            Issue.record("Expected an invalid initial state error")
        } catch GeneratedMachineError.invalidInitialState {
        } catch {
            Issue.record("Expected an invalid initial state error, got \(error)")
        }
    }

    @Test("a generated machine does not select an arbitrary initial state")
    func generatedMachineRequiresAnInitialStateWhenInitIsPlural() {
        do {
            _ = try SeededCounterMachine.makeMachine()
            Issue.record("Expected an ambiguous initial state error")
        } catch GeneratedMachineError.ambiguousInitialState {
        } catch {
            Issue.record("Expected an ambiguous initial state error, got \(error)")
        }
    }
}

@TLAModel
struct GeneratedRestrictedProcessDomain {
    enum Member: Int, CaseIterable, FiniteTLAValueDomain {
        case worker = 1

        static var defaultValue: Self { .worker }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .int(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedRestrictedProcessDomain") {
            Algorithm("GeneratedRestrictedProcessDomain", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(Member.all) { _ in
                    Do(TestControlLabel.increment) {
                        Assign(count, to: count + 1)
                    }
                }
            })
        }
    }
}

struct GeneratedRestrictedProcessDomainTests {
    @Test("a process declaration keeps its explicit member subset")
    func generatedModelUsesOnlyDeclaredProcessMembers() throws {
        let compilation = try GeneratedRestrictedProcessDomain.spec.compile()
        #expect(compilation.layout.actions.first?.bindings == [
            ActionBinding(name: "process", values: [.int(1)])
        ])
    }
}

@TLAModel
struct GeneratedSequentialCounter {
    static var spec: TLASpec {
        #spec("GeneratedSequentialCounter") {
            Algorithm("GeneratedSequentialCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.increment) {
                    Let(count + 1) { nextCount in
                        Assign(count, to: nextCount.expr)
                    }
                }
                Do(TestControlLabel.finish) {
                    Stop()
                }
            })
        }
    }
}

struct GeneratedSequentialMachineTests {
    @Test("a sequential Algorithm advances its typed state")
    func generatedSequentialAlgorithmAdvancesTypedState() throws {

        var model = try GeneratedSequentialCounter.makeMachine()
        let result = try model.send(.increment)
        #expect(result.after.count == 1)
    }
}

@TLAModel
struct GeneratedSimultaneousSwap {
    static var spec: TLASpec {
        #spec("GeneratedSimultaneousSwap") {
            Algorithm("GeneratedSimultaneousSwap", scoped: { scope in
                let left = scope.sharedVar("left", initial: 1)
                let right = scope.sharedVar("right", initial: 2)
                Do(TestControlLabel.swap) {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            })
        }
    }
}

struct GeneratedSimultaneousSwapTests {
    @Test("generated updates read one old state and commit together")
    func generatedMachineSwapsValues() throws {
        var model = try GeneratedSimultaneousSwap.makeMachine()

        let result = try model.send(.swap)

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
            Algorithm("GeneratedPairPattern", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                Do(TestControlLabel.choose) {
                    With(SetExpr<Pair<Int, Bool>>.literal(
                        Pair(first: 1, second: true),
                        Pair(first: 2, second: false)
                    )) { number, flag in
                        Assert((number.expr == 1) || !flag.expr)
                        Assign(selected, to: number.expr)
                    }
                }
            })
        }
    }
}

struct GeneratedPairPatternTests {
    @Test("a generated machine rejects an action with multiple valid successors")
    func generatedMachineRejectsAmbiguousPairSelection() throws {
        var model = try GeneratedPairPattern.makeMachine()
        do {
            _ = try model.send(.choose)
            Issue.record("Expected ambiguous action")
        } catch GeneratedMachineError.ambiguousAction {
        } catch {
            Issue.record("Expected ambiguous action, received \(error)")
        }
        #expect(model.state.selected == 0)
    }
}

@TLAModel
struct GeneratedRangeInitializedAlgorithm {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case clock

        static var defaultValue: Self { .clock }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedRangeInitializedAlgorithm") {
            Algorithm("GeneratedRangeInitializedAlgorithm", scoped: { scope in
                let hour = scope.sharedVar("hour", in: 1...3)
                Each(Node.all) { _ in
                    Do(TestControlLabel.advance) {
                        When(hour < 3)
                        Assign(hour, to: hour + 1)
                    }
                }
            })
        }
    }
}

struct GeneratedRangeInitializedAlgorithmTests {
    @Test("compiled initialization preserves every finite SharedVar value")
    func generatedRangePreservesEveryInitialHour() throws {
        let compilation = try GeneratedRangeInitializedAlgorithm.spec.compile()
        let hour = try #require(compilation.layout.variableID(named: "hour"))
        let initialHours = try CompiledRuntime(compilation: compilation).initialStates().map {
            try $0.value(for: hour).rendered(using: compilation.layout)
        }

        #expect(Set(initialHours) == [.int(1), .int(2), .int(3)])
    }
}

@TLAModel
struct GeneratedIntegerChoiceAlgorithm {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case only

        static var defaultValue: Self { .only }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedIntegerChoice") {
            Algorithm("GeneratedIntegerChoice", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                Each(Node.all) { _ in
                    Do(TestControlLabel.choose) {
                        Choose(1...3) { choice in
                            Assign(selected, to: choice.expr)
                        }
                    }
                }
            })
        }
    }
}

struct GeneratedIntegerChoiceAlgorithmTests {
    @Test("#spec retains a bounded integer choice")
    func generatedModelRetainsIntegerChoice() throws {
        let spec = GeneratedIntegerChoiceAlgorithm.spec
        let graph = try ModelChecker(compilation: try spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
        #expect(try Set(graph.states.values.compactMap { try value("selected", in: $0) }) == [.int(0), .int(1), .int(2), .int(3)])
    }
}

@TLAModel
struct GeneratedAlgorithmStateConstraint {
    static var spec: TLASpec {
        #spec("GeneratedAlgorithmStateConstraint") {
            Algorithm("GeneratedAlgorithmStateConstraint", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.advance) {
                    Assign(count, to: count + 1)
                }
                StateConstraint(count < 2)
            })
        }
    }
}

struct GeneratedAlgorithmStateConstraintTests {
    @Test("compiled exploration enforces an algorithm state constraint")
    func generatedModelPreservesStateConstraint() throws {
        let compilation = try GeneratedAlgorithmStateConstraint.spec.compile()
        #expect(compilation.semantics.constraint != nil)
        let graph = try ModelChecker(compilation: compilation, configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
        #expect(try Set(graph.states.values.compactMap { try value("count", in: $0) }) == [.int(0), .int(1)])
    }
}

@TLAModel
struct GeneratedProcessLocalInvariant {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        static var defaultValue: Self { .left }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Label: String, CaseIterable {
        case receive
    }

    static var spec: TLASpec {
        #spec("GeneratedProcessLocalInvariant") {
            Algorithm("GeneratedProcessLocalInvariant", scoped: { scope in
                Each(Node.all, scoped: { selfID, scope in
                    let count = scope.localVar("count", initial: 0)
                    Do(Label.receive) {
                        Skip()
                    }
                    Invariant("LocalCount") { count == 0 }
                    Invariant("ControlLocation") {
                        At(Label.receive, selfID) || Finished(selfID)
                    }
                })
            })
        }
    }
}

struct GeneratedProcessLocalInvariantTests {
    @Test("compilation preserves process-local invariants")
    func generatedModelPreservesProcessLocalInvariant() throws {
        let compilation = try GeneratedProcessLocalInvariant.spec.compile()
        #expect(compilation.semantics.invariants.map(\.name) == ["LocalCount", "ControlLocation"])
    }
}

@TLAModel
struct GeneratedDependentInitialAlgorithm {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        static var defaultValue: Self { .left }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case active
        case inactive

        static var defaultValue: Self { .active }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedDependentInitialAlgorithm") {
            Algorithm("GeneratedDependentInitialAlgorithm", scoped: { scope in
                let seed = scope.sharedVar("seed", in: SetExpr<Bool>.literal(false, true))
                let mirrors = scope.sharedVar("mirrors", initial: Function<Node, Phase>.mapping { node in
                    If(node == Node.left && seed == true, then: Phase.active, else: Phase.inactive)
                })
                Each(Node.all) { _ in
                    Do(TestControlLabel.stop) {
                        Assign(mirrors, to: mirrors)
                        Stop()
                    }
                }
            })
        }
    }
}

struct GeneratedDependentInitialAlgorithmTests {
    @Test("#spec preserves a dependent typed function initializer")
    func generatedModelPreservesDependentInitialStates() throws {
        let compilation = try GeneratedDependentInitialAlgorithm.spec.compile()
        let mirrors = try #require(compilation.layout.variableID(named: "mirrors"))
        let states = try CompiledRuntime(compilation: compilation).initialStates().map {
            try $0.value(for: mirrors).rendered(using: compilation.layout)
        }

        #expect(Set(states) == [
            .function([.string("left"): .string("inactive"), .string("right"): .string("inactive")]),
            .function([.string("left"): .string("active"), .string("right"): .string("inactive")])
        ])
    }
}

struct NestedAdapterConcurrencyTests {
    @Test("Nested actor executes through its canonical model")
    func nestedActorSharesCanonicalExecution() async throws {
        let actorLabel: NestedComposedCounter.Action = .advance
        var model = try NestedComposedCounter.makeMachine()
        let actor = try NestedComposedCounter.Actor()

        let expectedBefore = model.state
        #expect(actorLabel == .advance)
        #expect(expectedBefore.count == 0)

        let expected = try model.send(.advance)
        let acted = try await actor.send(.advance)

        #expect(acted.before == expected.before)
        #expect(acted.after == expected.after)
        #expect((await actor.state).count == 1)
    }

    @Test("Nested actor commits overlapping executions without stale write-back")
    func nestedActorExecutesOverlappingTransitionsAtomically() async throws {
        let actor = try NestedComposedCounter.Actor()
        async let first = actor.send(.advance)
        async let second = actor.send(.advance)
        _ = try await (first, second)

        #expect((await actor.state).count == 2)
    }
}

// MARK: - HourClock spec with invariants

@TLAModel
struct HourClock {
    static var spec: TLASpec {
        TLASpec("HourClock") {
            let hr = Var<Int>("hr")
            Variable(hr, 1)
            SwiftTLA.Action("Tick") { hr.becomes(hr + 1).when(hr < 12) }
            SwiftTLA.Action("Reset") { (hr == 12) && hr.becomes(1) }
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
            SwiftTLA.Action("inc") { x.becomes(x + 1).when(x < 5) }
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
            SwiftTLA.Action("incA") { a.becomes(a + 1).when(a < 2) }
            SwiftTLA.Action("incB") { b.becomes(b + 1).when(b < 2) }
            Invariant("sumLE4") { (a + b) <= 4 }
        }
    }
}

// MARK: - Builder-only: Var initial in constructor, no explicit Variable()

@TLAModel
struct BuilderOnlyClock {
    static var spec: TLASpec {
        #spec("BuilderOnlyClock") {
            Algorithm("BuilderOnlyClock", scoped: { scope in
                let hr = scope.sharedVar("hr", initial: 1)
                Do(TestControlLabel.tick) {
                    If(hr < 12) {
                        Assign(hr, to: hr + 1)
                    } else: {
                        Assign(hr, to: 1)
                    }
                }
                Invariant("valid") { hr >= 1 && hr <= 12 }
            })
        }
    }
}

@TLAModel
struct TwoCarElevatorMachine {
    static var spec: TLASpec {
        TLASpec("TwoCarElevatorMachine") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            SwiftTLA.Action("moveElevator", parameters: [ActionParameter("id", values: [1, 2])]) {
                floor.becomes(1)
            }
        }
    }

}

@TLAModel
struct ThreeParameterActionMachine {
    static var spec: TLASpec {
        TLASpec("ThreeParameterActionMachine") {
            let floor = Var<Int>("floor")
            Variable(floor, 0)
            SwiftTLA.Action("board", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(1)
            }
        }
    }

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
            SwiftTLA.Action("board", parameters: [
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
            SwiftTLA.Action("choose") {
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
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 2) }
        }
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

    @Test("Model macro generates a parameterized action")
    func modelParameterizedAction() throws {
        var elevator = try TwoCarElevatorMachine.makeMachine()
        _ = try elevator.send(.moveElevator(id: 1))
        #expect(elevator.floor == 1)
    }

    @Test("Generated actions retain every declared parameter")
    func generatedActionsRetainEveryDeclaredParameter() throws {
        var enabled = try ThreeParameterActionMachine.makeMachine()
        _ = try enabled.send(.board(person: 2, elevator: 20, direction: 200))
        #expect(enabled.floor == 1)
        #expect(ThreeParameterActionMachine.spec.actions[0].bindings.map(\.name) == [
            "person", "elevator", "direction"
        ])

        var invalidMiddleParameter = try ThreeParameterActionMachine.makeMachine()
        let before = invalidMiddleParameter.state
        #expect(throws: GeneratedMachineError.self) {
            try invalidMiddleParameter.send(.board(person: 2, elevator: 30, direction: 200))
        }
        #expect(invalidMiddleParameter.floor == 0)
        #expect(invalidMiddleParameter.state == before)
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
        let graph = try ModelChecker(compilation: try builder.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
        #expect(graph.transitions[.init(0)]?.map(\.label.arguments) == expectedArguments)

        let machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let initialActions = try machine.enabledActions()
        let expectedActions: [EndToEndThreeParameterActionMachine.Action] = [
            .board(person: 1, elevator: 10, direction: 100), .board(person: 1, elevator: 10, direction: 200),
            .board(person: 1, elevator: 20, direction: 100), .board(person: 1, elevator: 20, direction: 200),
            .board(person: 2, elevator: 10, direction: 100), .board(person: 2, elevator: 10, direction: 200),
            .board(person: 2, elevator: 20, direction: 100), .board(person: 2, elevator: 20, direction: 200)
        ]
        #expect(initialActions == expectedActions)
        #expect(try machine.isEnabled(.board(person: 2, elevator: 20, direction: 200)))
        #expect(try machine.isEnabled(.board(person: 2, elevator: 30, direction: 200)) == false)

        let renderedCalls = try builder.compile().renderedActions()
        #expect(renderedCalls.map(\.sourceName) == Array(repeating: "board", count: 8))
        #expect(renderedCalls.map(\.arguments) == expectedArguments)
        #expect(renderedCalls.map(\.renderedName) == [
            "board__0_0_0", "board__0_0_1", "board__0_1_0", "board__0_1_1",
            "board__1_0_0", "board__1_0_1", "board__1_1_0", "board__1_1_1"
        ])

        let compilation = try builder.compile()
        let initial = try firstCompiledState(in: compilation)
        let successor = try #require(try compiledSuccessors(
            named: "board",
            arguments: [.int(2), .int(20), .int(200)],
            in: compilation,
            from: initial
        ).first)
        #expect(try renderedValue(named: "floor", in: successor, compilation: compilation) == .int(222))
        #expect(try compiledSuccessors(
            named: "board",
            arguments: [.int(2), .int(30), .int(200)],
            in: compilation,
            from: initial
        ).isEmpty)
        #expect(try renderedValue(named: "floor", in: initial, compilation: compilation) == .int(0))

        var generatedMachine = try EndToEndThreeParameterActionMachine.makeMachine()
        let before = generatedMachine.state
        let evidence = try generatedMachine.send(.board(person: 2, elevator: 20, direction: 200))
        #expect(evidence.action == .board(person: 2, elevator: 20, direction: 200))
        #expect(evidence.after.floor == 222)
        #expect(throws: GeneratedMachineError.self) {
            try generatedMachine.send(.board(person: 2, elevator: 30, direction: 200))
        }
        #expect(generatedMachine.state.floor == 222)
        #expect(before.floor == 0)
    }

    @Test("Canonical generated machine preserves typed actions, transitions, and failed snapshots")
    func canonicalGeneratedMachineUsesCheckedThreeArgumentActions() throws {
        var machine = try ThreeParameterActionMachine.makeMachine()
        let action = ThreeParameterActionMachine.Action.board(person: 2, elevator: 20, direction: 200)
        let evidence = try machine.send(action)

        #expect(evidence.action == action)
        #expect(evidence.before.floor == 0)
        #expect(evidence.after.floor == 1)

        let before = machine.state
        #expect(throws: GeneratedMachineError.self) {
            try machine.send(.board(person: 2, elevator: 30, direction: 200))
        }
        #expect(machine.state == before)
    }

    @Test("Canonical generated execution publishes complete parameterized transitions")
    func canonicalGeneratedExecutionPreservesParameterizedTransition() throws {
        var machine = try EndToEndThreeParameterActionMachine.makeMachine()
        let before = machine.state

        let evidence = try machine.send(.board(person: 2, elevator: 20, direction: 200))
        let after = machine.state

        #expect(evidence.action == .board(person: 2, elevator: 20, direction: 200))
        #expect(evidence.before.floor == 0)
        #expect(evidence.after.floor == 222)
        #expect(before.floor == 0)
        #expect(after.floor == 222)
    }

    @Test("Actor returns the canonical three-argument transition")
    func actorMatchesCanonicalThreeArgumentTransition() async throws {
        var model = try ThreeParameterActionMachine.makeMachine()
        let expected = try model.send(.board(person: 2, elevator: 20, direction: 200))

        let actor = try ThreeParameterActionMachine.Actor()
        let acted = try await actor.send(.board(person: 2, elevator: 20, direction: 200))

        #expect(acted.action == expected.action)
        #expect(acted.before.floor == expected.before.floor)
        #expect(acted.after.floor == expected.after.floor)
    }

    @Test("Rejected generated labels preserve model and actor state")
    func rejectedActionsDoNotMutate() async throws {
        var model = try ThreeParameterActionMachine.makeMachine()
        let modelBefore = model.state
        do {
            _ = try model.send(.board(person: 2, elevator: 30, direction: 200))
            Issue.record("Expected rejected model action")
        } catch {
            #expect(error is GeneratedMachineError)
        }
        #expect(model.state == modelBefore)

        let actor = try ThreeParameterActionMachine.Actor()
        let actorBefore = await actor.state
        await #expect(throws: GeneratedMachineError.self) {
            try await actor.send(.board(person: 2, elevator: 30, direction: 200))
        }
        #expect(await actor.state == actorBefore)
    }

    @Test("Removed fixed-arity action syntax does not type check")
    func unsupportedActionParameterSyntaxDoesNotCompile() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/InvalidActionParameterAPI")
        let result = try runSwift(["build", "--package-path", fixture.path])

        #expect(result.status != 0)
        #expect(result.output.contains("Parameterized action 'singleParameter' requires a parameters list"))
        #expect(result.output.contains("Parameterized action 'multipleParameters' requires a parameters list"))
        #expect(result.output.contains("Parameterized action 'idParameter' requires a parameters list"))
        #expect(result.output.contains("Parameterized action 'namedParameters' requires a parameters list"))
        #expect(result.output.contains("value of type 'NamedAction' has no member 'binding'"))
        #expect(result.output.contains("value of type 'ActionDecl' has no member 'binding'"))
        #expect(result.output.contains("incorrect argument label in call (have 'name:body:binding:', expected 'name:body:bindings:')"))
    }

    @Test("Algorithm builder preserves an initialized clock")
    func builderOnlyClockRuntime() throws {
        let compilation = try BuilderOnlyClock.spec.compile()
        var machine = try BuilderOnlyClock.makeMachine()
        #expect(machine.state.hr == 1)
        #expect(try machine.send(.tick).after.hr == 2)
        let result = try ModelChecker(
            compilation: compilation,
            configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)
        ).check()
        if case .ok(let count) = result { #expect(count == 2) } else {
            #expect(Bool(false), "Expected the initial state and one successor")
        }
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
