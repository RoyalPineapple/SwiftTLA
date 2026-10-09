import Testing
import SwiftTLA

struct QuintupleValueTests {
    @Test("generated Swift transitions and TLA export preserve five heterogeneous tuple fields")
    func generatedTransitionAndFormalProjection() throws {
        var machine = try QuintupleValueModel.makeMachine()
        let token = try #require(TLAStateProjection.Token(validating: "value"))
        #expect(machine.state.value == Quintuple(
            first: 0, second: false, third: "open", fourth: 1, fifth: true))
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: token)
            == .tuple([.int(0), .bool(false), .string("open"), .int(1), .bool(true)]))

        _ = try machine.send(.advance)
        #expect(machine.state.value == Quintuple(
            first: 1, second: false, third: "open", fourth: 2, fifth: true))
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: token)
            == .tuple([.int(1), .bool(false), .string("open"), .int(2), .bool(true)]))
        #expect(try QuintupleValueModel.render().tlaBundle.root.tla
            .contains("<<0, FALSE, \"open\", 1, TRUE>>"))
    }
}
