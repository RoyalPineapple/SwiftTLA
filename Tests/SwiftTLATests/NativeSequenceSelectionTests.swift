import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct OrderedSequenceSelection {
    enum Step: String, CaseIterable { case select, empty }
    static var spec: TLASpec {
        #spec("OrderedSequenceSelection") {
            Algorithm("OrderedSequenceSelection", scoped: { scope in
                let items = scope.sharedVar("items", initial: TupleExpr<Int>.literal(3, 2, 2, 1))
                Do(Step.select) {
                    Assign(items, to: items.expr.selecting { member in member >= 2 })
                    Goto(Step.empty)
                }
                Do(Step.empty) {
                    Assign(items, to: items.expr.selecting { member in member > 99 })
                    Goto(Step.empty)
                }
            })
        }
    }
}

@Suite("Native sequence selection retains ordered occurrences")
struct NativeSequenceSelectionTests {
    @Test("Filtering preserves duplicates and order, including an empty result")
    func selectionMatchesFormalExecution() throws {
        let compilation = try OrderedSequenceSelection.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().first)
        let items = try #require(compilation.layout.testVariableID(named: "items"))
        let cases: [(String, OrderedSequenceSelection.Action, [Int])] = [
            ("select", .select, [3, 2, 2]), ("empty", .empty, []), ("empty", .empty, [])
        ]
        var machine = try OrderedSequenceSelection.makeMachine()
        for (name, action, expected) in cases {
            let id = try #require(compilation.layout.testActionID(named: name))
            formal = try #require(try runtime.successors(for: id, from: formal).first).state
            _ = try machine.send(action)
            #expect(machine.state.items == expected)
            #expect(try formal.value(for: items) == .tuple(expected.map(CompiledValue.integer)))
        }
    }
}
