import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct TypedParameterSelection {
    static var spec: TLASpec {
        #spec("TypedParameterSelection") { scope in
            let selected = scope.sharedVar("result", initial: 0)
            let choice = ActionParameter("selection", values: [1, 2])
            SwiftTLA.Action("choose", parameters: [choice]) {
                selected.becomes(choice + 1)
            }
        }
    }
}

struct TypedActionParameterTests {
    @Test("A typed parameter declaration owns its domain, formal name and body reference")
    func declaredParametersPreserveNativeAndFormalBindings() throws {
        let compilation = try TypedParameterSelection.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let selected = try #require(compilation.layout.testVariableID(named: "result"))
        let formal = try runtime.successors(from: initial)
        #expect(formal.map(\.arguments) == [[.integer(1)], [.integer(2)]])
        #expect(try formal.map { try $0.state.value(for: selected) } == [.integer(2), .integer(3)])
        let machine = try TypedParameterSelection.makeMachine()
        #expect(try machine.enabledActions() == [.choose(selection: 1), .choose(selection: 2)])
        for selection in [1, 2] {
            var next = machine
            _ = try next.send(.choose(selection: selection))
            #expect(next.state.result == selection + 1)
        }
    }
}


@TLAModel
private struct CollectionParameterUpdates {
    enum Key: String, CaseIterable, FiniteTLAValueDomain {
        case first, second
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
    }

    static var spec: TLASpec {
        #spec("CollectionParameterUpdates") { scope in
            let table = scope.sharedVar("table", initial: Function<Key, Int>.literal((.first, 0), (.second, 0)))
            let partial = scope.sharedVar("partial", initial: PartialFunction<Key, Int>.empty)
            let sequence = scope.sharedVar("sequence", initial: ZeroBasedSequence<Int>.literal(0, 0))
            let key = ActionParameter("key", values: Key.finiteValues)
            let value = ActionParameter("value", values: [1, 2])
            SwiftTLA.Action("replace", parameters: [key, value]) {
                table.becomes(table.updating(key, to: value))
                partial.becomes(partial.overriding(key, with: value))
                sequence.becomes(sequence.updating(0, to: value))
            }
        }
    }
}

extension TypedActionParameterTests {
    @Test("collection updates accept typed keys and replacement parameters")
    func collectionUpdatesPreserveParameters() throws {
        let compilation = try CollectionParameterUpdates.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let table = try #require(compilation.layout.testVariableID(named: "table"))
        let partial = try #require(compilation.layout.testVariableID(named: "partial"))
        let sequence = try #require(compilation.layout.testVariableID(named: "sequence"))
        let formal = try runtime.successors(from: initial)
        #expect(formal.count == 4)
        let machine = try CollectionParameterUpdates.makeMachine()
        #expect(try machine.enabledActions().count == 4)
        for key in CollectionParameterUpdates.Key.allCases {
            for value in [1, 2] {
                let expected = try #require(formal.first {
                    $0.arguments == [.string(key.rawValue), .integer(value)]
                })
                var next = machine
                _ = try next.send(.replace(key: key, value: value))
                #expect(next.state.table[key] == value)
                #expect(next.state.partial == [key: value])
                #expect(next.state.sequence == [0: value, 1: 0])
                let entries = Dictionary(uniqueKeysWithValues: next.state.table.map {
                    (CompiledValue.string($0.key.rawValue), CompiledValue.integer($0.value))
                })
                #expect(try expected.state.value(for: table) == .function(entries))
                #expect(try expected.state.value(for: partial) == .function([.string(key.rawValue): .integer(value)]))
                #expect(try expected.state.value(for: sequence) == .function([.integer(0): .integer(value), .integer(1): .integer(0)]))
            }
        }
    }
}

// These calls exercise the public protocol boundary without expression wrappers.
extension TypedActionParameterTests {
    @Test("Collection inputs and callbacks preserve typed parameter expressions")
    func collectionInputsAcceptTypedParameters() {
        let value = ActionParameter("value", values: [1, 2])
        let flag = ActionParameter("flag", values: [false, true])
        let members = Var("members", SetExpr<Int>(1, 2))
        let sequence = Var<TupleExpr<Int>>("sequence")
        #expect(members.mapping(file: "test", line: 1, column: 1) { _ in value }.stateExpr == members.expr.mapping(file: "test", line: 1, column: 1) { _ in value.expr }.stateExpr)
        #expect(members.union(members).stateExpr == members.expr.union(members.expr).stateExpr)
        #expect(sequence.concatenating(sequence).stateExpr == sequence.expr.concatenating(sequence.expr).stateExpr)
        #expect(SetExpr<Int>.literal(value, value + 1).stateExpr == .setLiteral([value.stateExpr, (value + 1).stateExpr]))
        #expect(TupleExpr<Int>.literal(value, 3).stateExpr == .tupleLiteral([value.stateExpr, 3.stateExpr]))
        #expect(Exists(in: members, file: "test", line: 1, column: 1) { _ in flag }.stateExpr ==
            Exists(in: members.expr, file: "test", line: 1, column: 1) { _ in flag.expr }.stateExpr)
    }
}
