import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct NestedSelectionMacro {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("NestedSelectionMacro") {
            Algorithm("NestedSelectionMacro", scoped: { scope in
                let number = scope.sharedVar("number", initial: 0)
                let text = scope.sharedVar("text", initial: "")
                let store = Macro { (pair: MacroParameter<Pair<Int, String>>) in
                    Assign(number, to: pair.expr.first())
                    Assign(text, to: pair.expr.second())
                }
                Do(Step.select) {
                    With(SetExpr<Int>.literal(1, 2)) { outer in
                        With(SetExpr<String>.literal("a", "b")) { inner in
                            store(Pair<Int, String>.literal(outer.expr, inner.expr))
                        }
                    }
                }
            })
        }
    }
}

@TLAModel
private struct NestedMultipleSelections {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("NestedMultipleSelections") {
            Algorithm("NestedMultipleSelections", scoped: { scope in
                let number = scope.sharedVar("number", initial: 0)
                let text = scope.sharedVar("text", initial: "")
                let flag = scope.sharedVar("flag", initial: false)
                let other = scope.sharedVar("other", initial: 0)
                Do(Step.select) {
                    With(SetExpr<Int>.literal(3), SetExpr<Bool>.literal(true)) { outer, outerFlag in
                        With(SetExpr<String>.literal("inner"), SetExpr<Int>.literal(8)) { inner, innerNumber in
                            Assign(number, to: outer.expr)
                            Assign(flag, to: outerFlag.expr)
                            Assign(text, to: inner.expr)
                            Assign(other, to: innerNumber.expr)
                        }
                    }
                }
            })
        }
    }
}

@TLAModel
private struct NestedChoiceAndSelection {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("NestedChoiceAndSelection") {
            Algorithm("NestedChoiceAndSelection", scoped: { scope in
                let number = scope.sharedVar("number", initial: 0)
                let text = scope.sharedVar("text", initial: "")
                Do(Step.select) {
                    Choose(1...2) { outer in
                        With(SetExpr<String>.literal("x")) { middle in
                            Choose(8...9) { inner in
                                Assign(number, to: outer.expr * 10 + inner.expr)
                                Assign(text, to: middle.expr)
                            }
                        }
                    }
                }
            })
        }
    }
}

@TLAModel
private struct NestedPairAndLetBindings {
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("NestedPairAndLetBindings") {
            Algorithm("NestedPairAndLetBindings", scoped: { scope in
                let number = scope.sharedVar("number", initial: 0)
                let text = scope.sharedVar("text", initial: "")
                let flag = scope.sharedVar("flag", initial: false)
                Do(Step.select) {
                    With(SetExpr<Pair<Int, Bool>>.literal(Pair(first: 3, second: true))) { outer, outerFlag in
                        With(SetExpr<Pair<String, Int>>.literal(Pair(first: "inner", second: 8))) { inner, innerNumber in
                            Let(outer.expr + 1) { first in
                                Let(innerNumber.expr + 1) { second in
                                    Assign(number, to: first.expr + second.expr)
                                    Assign(text, to: inner.expr)
                                    Assign(flag, to: outerFlag.expr)
                                }
                            }
                        }
                    }
                }
            })
        }
    }
}

@Suite struct LexicalSelectionIdentityTests {
    @Test("nested heterogeneous With values retain identity through statement macros")
    func nestedMacroArguments() throws {
        let results = try formalResults(NestedSelectionMacro.spec, variables: ["number", "text"])
        #expect(results == [
            [.integer(1), .string("a")], [.integer(1), .string("b")],
            [.integer(2), .string("a")], [.integer(2), .string("b")],
        ])
        var machine = try NestedSelectionMacro.makeMachine()
        let before = machine.state
        do {
            _ = try machine.send(.select)
            Issue.record("Four distinct lexical selections must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(machine.state == before)
    }

    @Test("nested multi-source With retains every outer and inner binding")
    func nestedMultipleSources() throws {
        #expect(try formalResults(NestedMultipleSelections.spec, variables: ["number", "flag", "text", "other"]) == [
            [.integer(3), .boolean(true), .string("inner"), .integer(8)]
        ])
        var machine = try NestedMultipleSelections.makeMachine()
        let state = try machine.send(.select).after
        #expect(state.number == 3)
        #expect(state.flag)
        #expect(state.text == "inner")
        #expect(state.other == 8)
    }

    @Test("nested Choose retains outer values across intervening With scopes")
    func mixedChoicesAndSelections() throws {
        #expect(try formalResults(NestedChoiceAndSelection.spec, variables: ["number", "text"]) == [
            [.integer(18), .string("x")], [.integer(19), .string("x")],
            [.integer(28), .string("x")], [.integer(29), .string("x")],
        ])
        var machine = try NestedChoiceAndSelection.makeMachine()
        #expect(try machine.enabledActions() == [.select])
        let before = machine.state
        do {
            _ = try machine.send(.select)
            Issue.record("Independent nested choices must retain distinct successors")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(machine.state == before)
    }

    @Test("nested Pair patterns and Let bindings keep independent lexical identities")
    func pairPatternsAndLocalValues() throws {
        #expect(try formalResults(NestedPairAndLetBindings.spec, variables: ["number", "text", "flag"]) == [
            [.integer(13), .string("inner"), .boolean(true)]
        ])
        var machine = try NestedPairAndLetBindings.makeMachine()
        let state = try machine.send(.select).after
        #expect(state.number == 13)
        #expect(state.text == "inner")
        #expect(state.flag)
    }

    private func formalResults(_ specification: TLASpec, variables: [String]) throws -> Set<[CompiledValue]> {
        let compilation = try specification.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "select"))
        let ids = try variables.map { name in try #require(compilation.layout.testVariableID(named: name)) }
        return try Set(runtime.successors(for: action, from: initial).map { successor in
            try ids.map { try successor.state.value(for: $0) }
        })
    }
}
