import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// A formal fixture makes domain traversal observable without exposing raw state.
@TLAModel
private struct IndependentCollectionDomains {
    struct Device: Identifiable, Sendable { let id: Int }
    static var spec: TLASpec {
        TLASpec("IndependentCollectionDomains") {
            let first = CollectionVar<Device, Int>("first")
            let second = CollectionVar<Device, Int>("second")
            let selected = Var<Int>("selected")
            ModelCollection(first, verificationScope: 2, initial: 0)
            ModelCollection(second, verificationScope: 2, initial: 0)
            Variable(selected, 0)
            CollectionAction("markSecond", on: second) { member in
                second.update(member, to: 1)
            }
            SwiftTLA.Action("chooseSecond") {
                selected.becomes(Expr<Int>(StateExpr.variable("second").applying(
                    StateExpr.any(from: StateExpr.variable("second").domain)
                )))
            }
        }
    }
}

@Suite("Native traversal retains independent collection domains")
struct NativeCollectionTraversalTests {
    @Test("CHOOSE uses its own collection order when another collection shares the ID type")
    func choosingFromSecondCollectionUsesItsOwnBinding() throws {
        let compilation = try IndependentCollectionDomains.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let mark = try #require(compilation.layout.testActionID(named: "markSecond"))
        let choose = try #require(compilation.layout.testActionID(named: "chooseSecond"))
        let second = try #require(compilation.layout.testVariableID(named: "second"))
        let selected = try #require(compilation.layout.testVariableID(named: "selected"))
        let firstFormalMember = try #require(compilation.layout.variables.first { $0.id == second }?.collection?.members.first)
        let marked = try #require(try runtime.successors(for: mark, from: initial).first {
            $0.arguments == [firstFormalMember]
        })
        let expected = try #require(try runtime.successors(for: choose, from: marked.state).first)
        #expect(try expected.state.value(for: selected) == .integer(1))
        #expect(try initial.value(for: second) != marked.state.value(for: second))

        // The old first-collection comparator ranks 20 before unknown 30,
        // making the wrong answer deterministic rather than Set-order-dependent.
        var machine = try IndependentCollectionDomains.makeMachine(first: [10, 20], second: [30, 20])
        _ = try machine.send(.markSecond(member: 30))
        _ = try machine.send(.chooseSecond)
        #expect(machine.state.selected == 1)
        #expect(try expected.state.value(for: selected) == .integer(machine.state.selected))
        #expect(machine.state.second == [30: 1, 20: 0])
    }
}
