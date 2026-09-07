import Testing
@testable import SwiftTLA
import UpstreamParity

struct BoulangerCorpusExecutionTests {
    @Test("Native process control and ambiguity agree with the formal Boulanger relation")
    func nativeProcessControl() throws {
        let compilation = try BoulangerModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initialStates = try runtime.initialStates()
        #expect(initialStates.count == 1)
        var formal = try #require(initialStates.first)
        var native = try BoulangerModel.makeMachine()
        let ncs = try #require(compilation.layout.testActionID(named: "ncs"))
        let e1 = try #require(compilation.layout.testActionID(named: "e1"))
        let num = try #require(compilation.layout.testVariableID(named: "num"))
        let flag = try #require(compilation.layout.testVariableID(named: "flag"))

        func compareVisibleStateAndInvariants() throws {
            let formalNumbers = CompiledValue.function(Dictionary(uniqueKeysWithValues:
                native.state.num.map { (.integer($0.key.rawValue), .integer($0.value)) }
            ))
            let formalFlags = CompiledValue.function(Dictionary(uniqueKeysWithValues:
                native.state.flag.map { (.integer($0.key.rawValue), .boolean($0.value)) }
            ))
            #expect(try formal.value(for: num) == formalNumbers)
            #expect(try formal.value(for: flag) == formalFlags)
            let violations = try compilation.semantics.invariants.filter {
                try !runtime.invariantHolds($0, in: formal)
            }.map(\.name)
            #expect(try native.violatedInvariants() == violations)
        }

        try compareVisibleStateAndInvariants()
        #expect(try Set(native.enabledActions()) == [
            .ncs(process: .one), .ncs(process: .two)
        ])
        let successors = try runtime.successors(for: ncs, from: formal).filter {
            $0.arguments == [.integer(1)]
        }
        #expect(successors.count == 1)
        formal = try #require(successors.first).state
        _ = try native.send(.ncs(process: .one))
        try compareVisibleStateAndInvariants()
        #expect(try Set(native.enabledActions()) == [
            .ncs(process: .two), .e1(process: .one)
        ])

        let choices = try runtime.successors(for: e1, from: formal).filter {
            $0.arguments == [.integer(1)]
        }
        #expect(Set(choices.map(\.state)).count == 2)
        let before = native.state
        do {
            _ = try native.send(.e1(process: .one))
            Issue.record("Distinct control successors must remain ambiguous")
        } catch GeneratedMachineError.ambiguousAction {}
        #expect(native.state == before)
        #expect(try native.isEnabled(.e1(process: .one)))
        try compareVisibleStateAndInvariants()
    }
}
