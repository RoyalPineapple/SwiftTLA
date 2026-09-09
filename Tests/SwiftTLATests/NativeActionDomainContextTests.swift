import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct NominalActionChoice {
    enum Value: String, CaseIterable, FiniteTLAValueDomain {
        case first, second
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }
    enum Step: String, CaseIterable { case select }
    static var spec: TLASpec {
        #spec("NominalActionChoice") {
            Algorithm("NominalActionChoice", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: Value.first)
                Do(Step.select) {
                    Choose(Value.all) { candidate in
                        When(candidate == Value.second)
                        Assign(selected, to: candidate.expr)
                    }
                }
            })
        }
    }
}

@Suite("Action choice domains preserve the selected native enum type")
struct NativeActionDomainContextTests {
    @Test("A literal finite domain is emitted using the chosen binder's nominal evidence")
    func contextualActionDomain() throws {
        let compilation = try NominalActionChoice.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "select"))
        let selected = try #require(compilation.layout.testVariableID(named: "selected"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        var machine = try NominalActionChoice.makeMachine()
        _ = try machine.send(.select)
        #expect(machine.state.selected == .second)
        #expect(try successor.state.value(for: selected) == .string("second"))
    }
}
