import Testing
import SwiftTLA

struct TripleHistoryTests {
    @Test("Generated transitions preserve all three heterogeneous tuple positions")
    func generatedTransitionAndFormalProjection() throws {
        var machine = try TripleHistoryModel.makeMachine()
        #expect(machine.state.history == Triple(first: 0, second: 0, third: "init"))
        let token = try #require(TLAStateProjection.Token(validating: "history"))
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: token)
            == .tuple([.int(0), .int(0), .string("init")]))

        _ = try machine.send(.record)
        #expect(machine.state.history == Triple(first: 1, second: 0, third: "recorded"))
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: token)
            == .tuple([.int(1), .int(0), .string("recorded")]))
        #expect(try TripleHistoryModel.render().tlaBundle.root.tla.contains("<<0, 0, \"init\">>"))
    }
}
