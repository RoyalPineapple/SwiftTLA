import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct FunctionUpdateConversion {
    enum Key: Int, CaseIterable, FiniteTLAValueDomain {
        case only = 0
        static var defaultValue: Self { .only }
        static let finiteValues = allCases
    }
    enum Node: Int, TLAValueType {
        case first = 1, second = 2
        static var defaultValue: Self { .first }
    }
    enum Step: String, CaseIterable { case idle }

    static var spec: TLASpec {
        #spec("FunctionUpdateConversion") {
            Algorithm("FunctionUpdateConversion", scoped: { scope in
                let nodes = scope.sharedVar("nodes", initial: Function<Key, Node>.literal((Key.only, Node.first)))
                let result = scope.sharedVar("result", initial: Function<Key, Int>.literal((Key.only, 0)))
                Do(Step.idle) { Assign(result, to: result.expr) }
            })
            // Formal fixture: the result has a wider value domain than its source.
            SwiftTLA.Action("convert") {
                ActionExpr.assign(.named("result"),
                    StateExpr.variable("nodes").updated(at: 0, to: 3))
            }
        }
    }
}

@Suite struct NativeFunctionUpdateConversionTests {
    @Test("function updates use the destination representation without narrowing replacement values")
    func updateUsesConvertedSource() throws {
        let compilation = try FunctionUpdateConversion.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "convert"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)

        var machine = try FunctionUpdateConversion.makeMachine()
        _ = try machine.send(.convert)
        #expect(machine.state.nodes == [.only: .first])
        #expect(machine.state.result == [.only: 3])
        #expect(try successor.state.value(for: result) == .function([.integer(0): .integer(3)]))
    }
}
