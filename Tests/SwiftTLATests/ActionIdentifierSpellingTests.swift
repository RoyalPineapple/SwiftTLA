import Testing
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
        let action = try #require(compilation.machineSurfacePlan.actions.first)
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
        #expect(compilation.machineSurfacePlan.actions.map(\.swiftIdentifier)
            == ["`class`", "`default`", "`switch`", "`repeat`", "repeat_"])
    }
}
