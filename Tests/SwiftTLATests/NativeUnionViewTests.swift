import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct CheckedUnionExecution {
    enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case first = 1, second = 2
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
    }
    enum Missing: String, TLAValueType {
        case value = "missing"
        static var defaultValue: Self { .value }
    }
    typealias Active = OneOf<Node, SetExpr<Node>>
    typealias Temporary = OneOf<Missing, Active>
    typealias FiniteChoice = OneOf<Node, Missing>
    typealias Overlap = OneOf<Node, Node>
    enum Step: String, CaseIterable { case load, inspect, collect, count, invalid }
    static var spec: TLASpec {
        #spec("CheckedUnionExecution") {
            Algorithm("CheckedUnionExecution", scoped: { scope in
                let temporary: SharedVariable<Temporary> = scope.sharedVar("temporary", initial: Temporary.first(.value))
                let finite: SharedVariable<FiniteChoice> = scope.sharedVar("finite", initial: FiniteChoice.first(.second))
                let overlapFirst = scope.sharedVar("overlapFirst", initial: Overlap.first(.second))
                let overlapSecond = scope.sharedVar("overlapSecond", initial: Overlap.second(.second))
                let selected = scope.sharedVar("selected", initial: Node.first)
                let finiteSelected = scope.sharedVar("finiteSelected", initial: Node.first)
                let size = scope.sharedVar("size", initial: 0)
                Do(Step.load) {
                    Assign(temporary, to: Temporary.second(Active.first(Node.second)))
                    Goto(Step.inspect)
                }
                Do(Step.inspect) {
                    Assign(selected, to: temporary.expr.assumingSecond(Active.self).assumingFirst(Node.self))
                    Assign(finiteSelected, to: finite.expr.assumingFirst(Node.self))
                    Goto(Step.collect)
                }
                Do(Step.collect) {
                    Assign(temporary, to: Temporary.second(Active.second(SetExpr<Node>.literal(.first, .second))))
                    Goto(Step.count)
                }
                Do(Step.count) {
                    Assign(size, to: temporary.expr.assumingSecond(Active.self).assumingSecond(SetExpr<Node>.self).cardinality)
                    Goto(Step.invalid)
                }
                Do(Step.invalid) {
                    Assign(selected, to: temporary.expr.assumingSecond(Active.self).assumingFirst(Node.self))
                }
            })
        }
    }
}

@Suite("Native union views check explicit alternative preconditions")
struct NativeUnionViewTests {
    @Test("Nested scalar and set alternatives execute without formal value decoding")
    func nestedViewsMatchFormalExecution() throws {
        let compilation = try CheckedUnionExecution.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().first)
        var machine = try CheckedUnionExecution.makeMachine()
        let actions: [(String, CheckedUnionExecution.Action)] = [
            ("load", .load), ("inspect", .inspect), ("collect", .collect), ("count", .count)
        ]
        for (name, action) in actions {
            let id = try #require(compilation.layout.testActionID(named: name))
            formal = try #require(try runtime.successors(for: id, from: formal).first).state
            _ = try machine.send(action)
        }
        #expect(machine.state.selected == .second)
        #expect(machine.state.overlapFirst == machine.state.overlapSecond)
        #expect(machine.state.size == 2)
        #expect(machine.state.finiteSelected == .second)
        let selected = try #require(compilation.layout.testVariableID(named: "selected"))
        let size = try #require(compilation.layout.testVariableID(named: "size"))
        #expect(try formal.value(for: selected) == .integer(2))
        #expect(try formal.value(for: size) == .integer(2))
        let invalid = try #require(compilation.layout.testActionID(named: "invalid"))
        #expect(throws: EvalError.noMatchingCase) { _ = try runtime.successors(for: invalid, from: formal) }
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) { _ = try machine.send(.invalid) }
        #expect(machine.state == before)
    }
}

@TLAModel
private struct InvalidFiniteUnionView {
    enum Node: Int, FiniteTLAValueDomain {
        case only = 1
        static var defaultValue: Self { .only }
        static let finiteValues: [Self] = [.only]
    }
    enum Missing: String, TLAValueType {
        case value = "missing"
        static var defaultValue: Self { .value }
    }
    typealias Choice = OneOf<Node, Missing>
    enum Step: String, CaseIterable { case inspect }
    static var spec: TLASpec {
        #spec("InvalidFiniteUnionView") {
            Algorithm("InvalidFiniteUnionView", scoped: { scope in
                let value = scope.sharedVar("value", initial: Choice.second(.value))
                let selected = scope.sharedVar("selected", initial: Node.only)
                Do(Step.inspect) {
                    Assign(selected, to: value.expr.assumingFirst(Node.self))
                }
            })
        }
    }
}

extension NativeUnionViewTests {
    @Test("An excluded finite alternative fails without changing native state")
    func excludedFiniteAlternative() throws {
        let compilation = try InvalidFiniteUnionView.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let formal = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "inspect"))
        #expect(throws: EvalError.noMatchingCase) { _ = try runtime.successors(for: action, from: formal) }
        var machine = try InvalidFiniteUnionView.makeMachine()
        let before = machine.state
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) { _ = try machine.send(.inspect) }
        #expect(machine.state == before)
    }
}
