import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct PartialFunctionExecution {
    enum Key: String, CaseIterable, FiniteTLAValueDomain {
        case first, second
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }
    enum Step: String, CaseIterable { case insert }
    static var spec: TLASpec {
        #spec("PartialFunctionExecution") {
            Algorithm("PartialFunctionExecution", scoped: { scope in
                let entries: SharedVariable<PartialFunction<Key, Int>> = scope.sharedVar(
                    "entries", initial: PartialFunction<Key, Int>.empty
                )
                Do(Step.insert) {
                    Assign(entries, to: entries.overriding(Key.first, with: 1))
                }
            })
        }
    }
}

@Suite struct NativePartialFunctionTests {
    @Test("empty partial functions accept an override without filling other domain members")
    func insertionMatchesFormalSuccessor() throws {
        let compilation = try PartialFunctionExecution.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let entries = try #require(compilation.layout.testVariableID(named: "entries"))
        let action = try #require(compilation.layout.testActionID(named: "insert"))
        #expect(try initial.value(for: entries) == .function([:]))
        let successors = try runtime.successors(for: action, from: initial)
        #expect(successors.count == 1)
        let successor = try #require(successors.first)
        var machine = try PartialFunctionExecution.makeMachine()
        #expect(machine.state.entries.isEmpty)
        let transition = try machine.send(.insert)
        #expect(transition.after.entries == [.first: 1])
        #expect(transition.after.entries[.second] == nil)
        #expect(try successor.state.value(for: entries) == .function([.string("first"): .integer(1)]))
    }
}
