import Testing
@testable import GeneratedMachineDocumentation
import SwiftTLA
import SwiftTLAMacros

struct GeneratedMachineDocumentationTests {
    @Test("authored field copies read preceding writes and export the same ordered assignments")
    func copiesUseTheWorkingState() throws {
        var machine = try OrderedFieldCopyModel.makeMachine()
        let after = try machine.send(.copy).after
        #expect(after == .init(x: 4, y: 2, z: 2))
        #expect(try machine.send(.copyThenReset).after == .init(x: 0, y: 7, z: 2))
        #expect(try machine.send(.resetThenCopy).after == .init(x: 0, y: 0, z: 2))
        #expect(try machine.send(.accumulate).after == .init(x: 3, y: 3, z: 2))
        let beforeOverflow = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 3])) {
            try machine.send(.overflow)
        }
        #expect(machine.snapshot == beforeOverflow)
        let reference = #spec("OrderedFieldCopyModel") {
            let copies = Algorithm { scope in
                let x = scope.sharedVar(initial: 2)
                let y = scope.sharedVar(initial: 3)
                let z = scope.sharedVar(initial: 4)
                Do(OrderedFieldCopyModel.Step.copy) {
                    Assign(y, to: x)
                    Assign(x, to: z)
                    Assign(z, to: y)
                }
                Do(OrderedFieldCopyModel.Step.copyThenReset) {
                    Assign(x, to: 7)
                    Assign(y, to: x)
                    Assign(x, to: 0)
                }
                Do(OrderedFieldCopyModel.Step.resetThenCopy) {
                    Assign(x, to: 7)
                    Assign(x, to: 0)
                    Assign(y, to: x)
                }
                Do(OrderedFieldCopyModel.Step.accumulate) {
                    Assign(y, to: y + 3)
                    Assign(x, to: x + y)
                }
                Do(OrderedFieldCopyModel.Step.overflow) {
                    Assign(x, to: 9_223_372_036_854_775_807)
                    Assign(x, to: x + y)
                }
            }
            copies
        }
        let expected = try reference.compile().render().tlaBundle
        let built = try OrderedFieldCopyModel.spec.compile().render().tlaBundle
        let emitted = try OrderedFieldCopyModel.render().tlaBundle
        #expect(built.tla == expected.tla)
        #expect(emitted.tla == expected.tla)
        #expect(built.cfg == expected.cfg)
        #expect(emitted.cfg == expected.cfg)
    }

    @Test("integer += runs the same update that explicit assignment exports")
    func integerAdditionAssignment() throws {
        var machine = try SequentialCounter.makeMachine()
        #expect(try machine.send(.advance).after.value == 1)
        #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try machine.send(.advance) }

        let explicit = #spec("SequentialCounter") {
            let counter = Algorithm(scoped: { scope in
                let value = scope.sharedVar(initial: 0)
                Do(SequentialCounter.Step.advance, when: value < 5) {
                    Assign(value, to: value + 1)
                    Stop()
                }
            })
            counter
        }
        let expected = try explicit.compile().render().tlaBundle
        let built = try SequentialCounter.spec.compile().render().tlaBundle
        let actual = try SequentialCounter.render().tlaBundle
        #expect(built.tla == expected.tla)
        #expect(actual.tla == expected.tla)
        #expect(actual.cfg == expected.cfg)
    }

    @Test("integer += reads preceding writes and preserves the snapshot on overflow")
    func additionAssignmentEvaluatesTheWholeRightOperand() throws {
        var successful = try AdditionAssignmentModel.makeMachine(.init(value: 0))
        #expect(try successful.send(.advance).after.value == Int.max)

        var failing = try AdditionAssignmentModel.makeMachine(.init(value: 1))
        let before = failing.snapshot
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max - 3, 4])) {
            try failing.send(.advance)
        }
        #expect(failing.snapshot == before)
    }

    @Test("the documented generated export exposes its module and configuration")
    func generatedExportMatchesGuide() throws {
        let bundle = try BoundedCounter.render().tlaBundle
        #expect(bundle.root.name == "BoundedCounter")
        #expect(bundle.tla.contains("---- MODULE BoundedCounter ----"))
        #expect(bundle.cfg.contains("SPECIFICATION Spec"))
    }

    @Test("the clock tick selects the ordinary, minute, hour, and midnight updates",
          arguments: [(12, 59, 58, 12, 59, 59), (16, 19, 59, 16, 20, 0),
                      (12, 59, 59, 13, 0, 0), (23, 59, 59, 0, 0, 0)])
    func readmeClockRollovers(_ time: (Int, Int, Int, Int, Int, Int)) throws {
        let initial = ClockModel.State(hour: time.0, minute: time.1, second: time.2)
        var machine = try ClockModel.makeMachine(initial)
        let transition = try machine.send(.tick)
        #expect(transition.before == initial)
        #expect(transition.after == .init(hour: time.3, minute: time.4, second: time.5))
        #expect(machine.state == transition.after)
        #expect(try machine.violatedInvariants(checking: [.validTime], atLevel: 1).isEmpty)
    }

    @Test("an inclusive hour range preserves the explicit bounds and their midnight failure")
    func hourRangePreservesBounds() throws {
        let explicit = #spec("HourRangeFixture") {
            let ValidHour = Invariant()
            let clock = Algorithm { scope in
                let hour = scope.sharedVar(initial: -1)
                Loop(HourRangeFixture.Step.tick) { hour += 1 }
                ValidHour { hour >= 0 && hour <= 23 }
            }
            clock
        }
        let expected = try explicit.compile().render().tlaBundle
        let authored = try HourRangeFixture.spec.compile().render().tlaBundle
        let generated = try HourRangeFixture.render().tlaBundle
        #expect(authored.tla == expected.tla)
        #expect(generated.tla == expected.tla)
        #expect(authored.cfg == expected.cfg)
        #expect(generated.cfg == expected.cfg)

        var clock = try HourRangeFixture.makeMachine()
        #expect(try clock.violatedInvariants(checking: [.ValidHour], atLevel: 1) == [.ValidHour])
        for hour in 0...23 {
            #expect(try clock.send(.tick).after.hour == hour)
            #expect(try clock.violatedInvariants(checking: [.ValidHour], atLevel: 1).isEmpty)
        }
        guard case .counterexample(let witness) = try clock.check(
            properties: [.ValidHour], checkDeadlock: false, maximumStates: 2
        ) else {
            Issue.record("Expected one tick from 23 to violate ValidHour")
            return
        }
        #expect(witness.violations == [.invariant(.ValidHour)])
        #expect(witness.trace.map(\.action) == [nil, .tick])
        #expect(try clock.replay(witness).state.hour == 24)
    }

    @Test("two tick sends cross midnight and advance one more second")
    func ticksAcrossMidnight() throws {
        var clock = try ClockModel.makeMachine(.init(hour: 23, minute: 59, second: 59))
        let midnight = try clock.send(.tick)
        #expect(midnight.after == .init(hour: 0, minute: 0, second: 0))
        let next = try clock.send(.tick)
        #expect(next.before == midnight.after)
        #expect(next.after == .init(hour: 0, minute: 0, second: 1))
    }

    @Test("guarded alternatives retain overlapping successors and skip later guards of a disabled alternative")
    func overlappingAlternatives() throws {
        for (input, expected) in [(0, [3, 4]), (1, [4, 5]), (2, [])] {
            var machine = try OverlappingGuards.makeMachine(.init(value: input))
            let before = machine.snapshot
            let successors = try machine.successors(for: .pick)
            #expect(successors.map(\.state.value).sorted() == expected)
            let error: GeneratedMachineError = expected.isEmpty ? .noMatchingSuccessor : .ambiguousAction
            #expect(throws: error) { try machine.send(.pick) }
            #expect(machine.snapshot == before)
        }
    }

    @Test("bounded machine preserves state when a disabled action is rejected")
    func disabledActionRetainsSnapshot() throws {
        var machine = try BoundedCounter.makeMachine()
        let transition = try machine.send(.advance)
        let beforeFailure = machine.state

        #expect(transition.before.value == 0)
        let isEnabled = try machine.isEnabled(.advance)
        #expect(isEnabled == false)
        #expect(transition.after.value == 1)
        #expect(throws: GeneratedMachineError.self) {
            try machine.send(.advance)
        }
        #expect(machine.state == beforeFailure)
    }

    @Test("checking a completed counter explores from its current snapshot")
    func checksFromCurrentSnapshot() throws {
        var counter = try SequentialCounter.makeMachine()
        _ = try counter.send(.advance)
        let completed = counter.snapshot
        let result = try counter.check(properties: [], checkDeadlock: false, maximumStates: 1)
        guard case .exhausted(let graph) = result else {
            Issue.record("Expected a complete graph from the stopped counter")
            return
        }
        #expect(graph.initialStates == [completed])
        #expect(counter.snapshot == completed)
    }

    @Test("a standalone consumer checks its generated machine without parity infrastructure")
    func checksGeneratedMachineWithoutTLC() throws {
        var sawAdvance = false
        let result = try MachineValidator.run(
            initialMachines: [BoundedCounter.makeMachine()], maximumStates: 10,
            checking: ModelChecks(properties: [], checkDeadlock: false),
            stopOnViolation: false) { event in
                if case .edge(_, .advance, _) = event { sawAdvance = true }
            }
        guard case .exhausted = result.completion else {
            Issue.record("Expected exhaustive native checking")
            return
        }
        #expect(result.states == 2)
        #expect(sawAdvance)
    }

    @Test("generated actor owns the generated machine")
    func generatedActorExposesDocumentedBehavior() async throws {
        let actor = try CounterHost.Actor()

        let transition = try await actor.send(.advance)
        let state = await actor.state
        #expect(state == transition.after)
    }
}
