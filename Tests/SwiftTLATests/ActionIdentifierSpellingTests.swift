import Testing
@testable import SwiftTLAPlugin
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct KeywordActionExecution {
    enum Step: String, CaseIterable { case `repeat` }
    static var spec: TLASpec {
        #spec("KeywordActionExecution") {
            Algorithm("KeywordActionExecution", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.repeat) {
                    Assign(count, to: count.expr + 1)
                }
            })
        }
    }
}

struct ActionIdentifierSpellingTests {
    @Test("Keyword action labels retain their formal names and compile as Swift cases")
    func keywordActionDispatches() throws {
        let compilation = try KeywordActionExecution.spec.compile()
        let action = try #require(MachineSurfacePlan(layout: compilation.layout, semantics: compilation.semantics).actions.first)
        #expect(compilation.layout.actions[action.compiledAction.ordinal].declaration.name == "repeat")
        #expect(action.swiftIdentifier == "`repeat`")
        var machine = try KeywordActionExecution.makeMachine()
        #expect(try machine.isEnabled(.repeat))
        #expect(try machine.send(.repeat).after.count == 1)
    }

    @Test("Swift keyword escaping preserves distinct generated action identities")
    func keywordIdentifiersRemainDistinct() throws {
        let compilation = try canonicalTestSpec(
            variables: [("value", .value(.int(0)))],
            actions: ["class", "default", "switch", "repeat", "repeat!"].map {
                (name: $0, body: ActionExpr.unchanged(.named("value")), bindings: [])
            },
            invariants: []
        ).compile()
        #expect(compilation.layout.actions.map { $0.declaration.name }
            == ["class", "default", "switch", "repeat", "repeat!"])
        #expect(try MachineSurfacePlan(layout: compilation.layout, semantics: compilation.semantics).actions.map(\.swiftIdentifier)
            == ["`class`", "`default`", "`switch`", "`repeat`", "repeat_"])
    }
}

@TLAModel
private struct KeywordStateExecution {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("KeywordStateExecution") {
            Algorithm("KeywordStateExecution", scoped: { scope in
                let value = scope.sharedVar("class", initial: 0)
                Do(Step.advance) { Assign(value, to: value.expr + 1) }
            })
        }
    }
}

// Formal boundary fixture supplies arbitrary formal action and parameter names.
@TLAModel
private struct WildcardActionExecution {
    static var spec: TLASpec {
        TLASpec("WildcardActionExecution") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("_", parameters: [ActionParameter("class", values: [1, 2])]) {
                value.becomes(1)
            }
        }
    }
}

extension ActionIdentifierSpellingTests {
    @Test("Keyword state fields and action parameters retain named Swift access")
    func keywordFieldsAndBindingsCompile() throws {
        var stateMachine = try KeywordStateExecution.makeMachine()
        #expect(stateMachine.state.class == 0)
        #expect(try stateMachine.send(.advance).after.class == 1)
        var actionMachine = try WildcardActionExecution.makeMachine()
        #expect(try actionMachine.send(.action__(class: 1)).after.value == 1)
        let compilation = try WildcardActionExecution.spec.compile()
        let surface = try MachineSurfacePlan(layout: compilation.layout, semantics: compilation.semantics)
        #expect(surface.actions.first?.bindings.first?.formalName == "class")
        #expect(surface.actions.first?.bindings.first?.swiftIdentifier == "`class`")
    }

    @Test("Unspellable field and binding names fail at the generated surface boundary")
    func malformedNamesAreRejected() throws {
        for name in ["_", "two words", "total-count", "1value"] {
            #expect(throws: CompilationDiagnostic.self) {
                try MachineSurfacePlan.Variable(formalName: name, storageOrdinal: 0, collection: nil)
            }
            #expect(throws: CompilationDiagnostic.self) {
                try MachineSurfacePlan.Binding(formalName: name, isPublic: true)
            }
        }
    }
}
