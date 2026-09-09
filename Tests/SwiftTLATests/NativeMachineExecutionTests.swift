import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct BoundedExecutionCounter {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("BoundedExecutionCounter") {
            Algorithm("BoundedExecutionCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                While(Step.advance, true) {
                    When(count < 3)
                    Assign(count, to: count + 1)
                }
            })
        }
    }
}

@TLAModel
private struct SimultaneousExecutionSwap {
    enum Step: String, CaseIterable { case swap }
    static var spec: TLASpec {
        #spec("SimultaneousExecutionSwap") {
            Algorithm("SimultaneousExecutionSwap", scoped: { scope in
                let left = scope.sharedVar("left", initial: 1)
                let right = scope.sharedVar("right", initial: 2)
                While(Step.swap, true) {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            })
        }
    }
}

@TLAModel
private struct ConstrainedExecutionChoice {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("ConstrainedExecutionChoice") {
            Algorithm("ConstrainedExecutionChoice", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                While(Step.select, true) {
                    Choose(1...3) { choice in
                        Assign(selected, to: choice.expr)
                    }
                }
                StateConstraint(selected <= 1)
            })
        }
    }
}

@TLAModel
private struct AmbiguousExecutionChoice {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("AmbiguousExecutionChoice") {
            Algorithm("AmbiguousExecutionChoice", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                While(Step.select, true) {
                    Choose(1...3) { choice in
                        Assign(selected, to: choice.expr)
                    }
                }
                StateConstraint(selected <= 2)
            })
        }
    }
}

private extension AmbiguousExecutionChoice {
    // Exercise the generated relation before send applies its uniqueness rule.
    func candidateStates(for action: Action) throws -> [State] {
        try _successors(for: action).map(\.state)
    }
}

@Suite("Generated execution agrees with the formal relation")
struct NativeMachineExecutionTests {
    @Test("Bounded counter preserves initial states, enabledness, and every reachable step")
    func counterMatchesFormalExploration() throws {
        let compilation = try BoundedExecutionCounter.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().only)
        let count = try #require(compilation.layout.testVariableID(named: "count"))
        let advance = try #require(compilation.layout.testActionID(named: "advance"))
        var machine = try BoundedExecutionCounter.makeMachine()
        var observed = Set<Int>()

        for expected in 0...3 {
            observed.insert(machine.state.count)
            #expect(machine.state.count == expected)
            #expect(try formal.value(for: count) == .integer(machine.state.count))
            let successors = try runtime.successors(for: advance, from: formal)
            #expect(try machine.isEnabled(.advance) == !successors.isEmpty)
            #expect(try machine.enabledActions() == (successors.isEmpty ? [] : [.advance]))
            if let successor = successors.only {
                let before = machine.state
                let transition = try machine.send(.advance)
                #expect(transition.before == before)
                #expect(transition.after == machine.state)
                formal = successor.state
            }
        }
        let before = machine.state
        do {
            _ = try machine.send(.advance)
            Issue.record("A disabled action must fail")
        } catch GeneratedMachineError.noMatchingSuccessor {}
        #expect(machine.state == before)
        let exploration = try ModelChecker(compilation: compilation, configuration: .init(
            maximumStateLimit: 16, symmetryReduction: .disabled
        )).explore()
        let checked = try Set(exploration.compiledStates.values.map { try $0.value(for: count) })
        #expect(checked == Set(observed.map(CompiledValue.integer)))
    }

    @Test("Simultaneous assignments preserve old-state reads across a complete cycle")
    func swapMatchesFormalSuccessors() throws {
        let compilation = try SimultaneousExecutionSwap.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().only)
        let swap = try #require(compilation.layout.testActionID(named: "swap"))
        let left = try #require(compilation.layout.testVariableID(named: "left"))
        let right = try #require(compilation.layout.testVariableID(named: "right"))
        var machine = try SimultaneousExecutionSwap.makeMachine()
        for _ in 0..<2 {
            let before = machine.state
            let successor = try #require(try runtime.successors(for: swap, from: formal).only)
            _ = try machine.send(.swap)
            #expect(machine.state.left == before.right)
            #expect(machine.state.right == before.left)
            #expect(try successor.state.value(for: left) == .integer(machine.state.left))
            #expect(try successor.state.value(for: right) == .integer(machine.state.right))
            formal = successor.state
        }
        #expect(machine.state.left == 1)
        #expect(machine.state.right == 2)
    }

    @Test("Target constraints resolve choice before generated ambiguity checks")
    func constrainedChoiceMatchesFormalSuccessors() throws {
        let compilation = try ConstrainedExecutionChoice.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().only)
        let select = try #require(compilation.layout.testActionID(named: "select"))
        let selected = try #require(compilation.layout.testVariableID(named: "selected"))
        let successor = try #require(try runtime.successors(for: select, from: initial).only)
        var machine = try ConstrainedExecutionChoice.makeMachine()
        #expect(try machine.enabledActions() == [.select])
        _ = try machine.send(.select)
        #expect(machine.state.selected == 1)
        #expect(try successor.state.value(for: selected) == .integer(machine.state.selected))
    }

    @Test("Multiple formal successors remain ambiguous without committing a partial state")
    func ambiguousChoiceIsTransactional() throws {
        let compilation = try AmbiguousExecutionChoice.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().only)
        let select = try #require(compilation.layout.testActionID(named: "select"))
        let successors = try runtime.successors(for: select, from: initial)
        #expect(Set(successors.map(\.state)).count == 2)
        var machine = try AmbiguousExecutionChoice.makeMachine()
        let before = machine.state
        let selected = try #require(compilation.layout.testVariableID(named: "selected"))
        let formalValues = try Set(successors.map { try $0.state.value(for: selected) })
        let nativeValues = try Set(machine.candidateStates(for: .select).map {
            CompiledValue.integer($0.selected)
        })
        #expect(nativeValues == formalValues)
        #expect(try machine.isEnabled(.select))
        #expect(try machine.enabledActions() == [.select])
        do {
            _ = try machine.send(.select)
            Issue.record("Distinct successors must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(machine.state == before)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
