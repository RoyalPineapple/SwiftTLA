import Testing
@testable import SwiftTLA

struct TypedActionParameterTests {
    @Test("A typed step argument retains its domain, formal call, and assigned result")
    func declaredParametersPreserveNativeAndFormalBindings() throws {
        let machine = try TypedParameterSelection.makeMachine()
        #expect(try machine.enabledActions() == [.choose(selection: 1), .choose(selection: 2)])
        let result = try #require(TLAStateProjection.Token(validating: "result"))
        for selection in [1, 2] {
            var next = machine
            _ = try next.send(.choose(selection: selection))
            #expect(next.state.result == selection + 1)
            #expect(try machine.formalCall(for: .choose(selection: selection)) ==
                FormalActionCall(name: "choose", arguments: [.int(selection)]))
            #expect(try next.formalProjection(of: next.snapshot).value(for: result) == .int(selection + 1))
        }
    }

    @Test("Evaluation failures quantify every typed action argument and remain selected")
    func parameterizedEvaluationFailuresCoverEveryInvocation() throws {
        let rendered = try TypedParameterSelection.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains("__SwiftTLAOverflowOperands0(selection) == <<selection, 1>>"))
        #expect(definitions.contains(#"__SwiftTLAEvaluationOK == ~((\E selection \in {1, 2}: __SwiftTLAOverflowFailure0(selection)))"#))
        let selected = try rendered.checkSelection(checking: [], checkDeadlock: false)
        #expect(selected.intrinsicInvariantNames == ["__SwiftTLAEvaluationOK"])
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }

    @Test("Symbolic parameter failures retain the action guard and domain")
    func symbolicEvaluationFailuresUseGuardedDomain() throws {
        let scenario = try #require(BoundStepEnabledness.validationScenarios().first)
        let rendered = try scenario.render()
        let definitions = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(definitions.contains { $0.hasPrefix("__SwiftTLAOverflowFailure0(amount) == (((count < 2)) = TRUE /\\ ") })
        #expect(definitions.contains("__SwiftTLAOverflowOperands0(amount) == <<count, amount>>"))
        #expect(definitions.contains(#"__SwiftTLAEvaluationOK == ~((\E amount \in choices: __SwiftTLAOverflowFailure0(amount)))"#))
        let cfg = try #require(rendered.tlaBundle(checking: [], checkDeadlock: false).root.cfg)
        #expect(cfg.contains("INVARIANT __SwiftTLAEvaluationOK\n"))
    }
}

extension TypedActionParameterTests {
    @Test("collection updates accept typed keys and replacement parameters")
    func collectionUpdatesPreserveParameters() throws {
        let machine = try CollectionParameterUpdates.makeMachine()
        #expect(try machine.enabledActions().count == 4)
        let table = try #require(TLAStateProjection.Token(validating: "table"))
        let partial = try #require(TLAStateProjection.Token(validating: "partial"))
        let sequence = try #require(TLAStateProjection.Token(validating: "sequence"))
        for key in CollectionParameterUpdates.Key.allCases {
            for value in [1, 2] {
                var next = machine
                _ = try next.send(.replace(key: key, value: value))
                #expect(next.state.table[key] == value)
                #expect(next.state.partial == [key: value])
                #expect(next.state.sequence == [0: value, 1: 0])
                #expect(try machine.formalCall(for: .replace(key: key, value: value)) ==
                    FormalActionCall(name: "replace", arguments: [.string(key.rawValue), .int(value)]))
                let projected = try next.formalProjection(of: next.snapshot)
                #expect(projected.value(for: table) == .function([
                    .string("first"): .int(key == .first ? value : 0),
                    .string("second"): .int(key == .second ? value : 0)
                ]))
                #expect(projected.value(for: partial) == .function([.string(key.rawValue): .int(value)]))
                #expect(projected.value(for: sequence) == .function([.int(0): .int(value), .int(1): .int(0)]))
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
