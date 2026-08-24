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
            Action("procedure.work.enter") { value.becomes(1) }
            Action("procedure_work_enter") { value.becomes(2) }
            Action("step-2") { value.becomes(3) }
        }
    }
}

@TLAModel
private struct InvocationNamedActionModel {
    static var spec: TLASpec {
        #spec("InvocationNamedActionModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            Action("toInvocation") { value.becomes(1) }
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
    enum Node: String, CaseIterable {
        case left
        case right

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
    enum Member: Int, CaseIterable {
        case worker = 1
        /// A value that is valid in state, but not a member of the process
        /// domain. This is the usual shape for an optional parent pointer.
        case none = 0


    }

    static var spec: TLASpec {
        #spec("GeneratedRestrictedProcessDomain") {
            Algorithm("GeneratedRestrictedProcessDomain", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(FiniteDomain([.worker])) { _ in
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
    func generatedModelUsesOnlyDeclaredProcessMembers() {
        #expect(GeneratedRestrictedProcessDomain.spec.actions.first?.bindings == [
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
    @Test("a generated model preserves tuple-pattern selection")
    func generatedMachineAppliesPairPatternBindings() throws {

        var model = try GeneratedPairPattern.makeMachine()
        let result = try model.send(.choose)

        #expect([1, 2].contains(result.after.selected))
    }
}

@TLAModel
struct GeneratedRangeInitializedAlgorithm {
    enum Node: String, CaseIterable {
        case clock


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
    @Test("#spec independently parses a finite SharedVar initial range")
    func generatedRangePreservesEveryInitialHour() throws {
        let compilation = try GeneratedRangeInitializedAlgorithm.spec.compile()
        let hour = try #require(compilation.layout.variableID(named: "hour"))
        let initialHours = try CompiledRuntime(compilation: compilation).initialStates().map {
            try $0.value(for: hour).rendered(using: compilation.layout)
        }

        #expect(Set(initialHours) == [.int(1), .int(2), .int(3)])
        #expect(GeneratedRangeInitializedAlgorithm.spec.variables.first { $0.name == "hour" }?.initialSet
            == .setLiteral([.value(.int(1)), .value(.int(2)), .value(.int(3))]))
    }
}

@TLAModel
struct GeneratedIntegerChoiceAlgorithm {
    enum Node: String, CaseIterable {
        case only

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
    @Test("#spec preserves an algorithm-local state constraint through both construction paths")
    func generatedModelPreservesStateConstraint() throws {
        #expect(GeneratedAlgorithmStateConstraint.spec.constraint
            == .lessThan(.variable("count"), .value(.int(2))))
        let graph = try ModelChecker(compilation: try GeneratedAlgorithmStateConstraint.spec.compile(), configuration: try .init(maximumStateLimit: 100_000)).exploreGraph()
        #expect(try Set(graph.states.values.compactMap { try value("count", in: $0) }) == [.int(0), .int(1)])
    }
}

@TLAModel
struct GeneratedProcessLocalInvariant {
    enum Node: String, CaseIterable {
        case left
        case right

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
        let actorLabel: NestedComposedCounter.Actor.Action = .advance
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
            Action("moveElevator", parameters: [ActionParameter("id", values: [1, 2])]) {
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
            Action("board", parameters: [
                ActionParameter("person", values: [1, 2]),
                ActionParameter("elevator", values: [10, 20]),
                ActionParameter("direction", values: [100, 200])
            ]) {
                floor.becomes(1)
            }
        }
    }

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

    @TLAActor
    actor Actor {}
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
        _ = try elevator.send(.moveElevator(member: 1))
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

        let compilation = try builder.compile()
        let action = try #require(compilation.layout.actionID(named: "board"))
        let initial = try #require(try compilation.initialStateProjections().first)
        let formalFloor = try #require(TLAStateProjection.Token(validating: "floor"))
        let successor = try #require(try compilation.successors(
            for: action,
            arguments: [.int(2), .int(20), .int(200)],
            from: initial
        ).first)
        #expect(successor.value(for: formalFloor) == .int(222))
        #expect(try compilation.successors(
            for: action,
            arguments: [.int(2), .int(30), .int(200)],
            from: initial
        ).isEmpty)
        #expect(initial.value(for: formalFloor) == .int(0))

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
        #expect(throws: GeneratedMachineError.self) {
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
        let spec = BuilderOnlyClock.spec
        #expect(spec.variables.count == 1)
        #expect(spec.variables[0].name == "hr")
        #expect(spec.variables[0].initial == .int(1))
        let result = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 100)).check()
        if case .ok(let count) = result { #expect(count == 12) } else {
            #expect(Bool(false), "Expected 12 states")
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
