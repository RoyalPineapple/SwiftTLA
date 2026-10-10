import SwiftTLA
import Testing

struct GeneratedFunctionStateTests {
    @Test("a bound function mapping replaces typed state through generated transitions")
    func replacesFunctionState() throws {
        var machine = try GeneratedFunctionStateModel.makeMachine()
        #expect(machine.state.clock[.one] == 0)
        #expect(machine.state.clock[.two] == 0)

        let transition = try machine.send(.replace)
        #expect(transition.after.clock[.one] == 10)
        #expect(transition.after.clock[.two] == 20)
        let clock = try #require(TLAStateProjection.Token(validating: "clock"))
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: clock)
            == .function([.int(1): .int(10), .int(2): .int(20)]))
        #expect(try !machine.isEnabled(.replace))

        let graph = try ReachabilityGraph(
            initialMachines: GeneratedFunctionStateModel.initialMachines(), maximumStates: 10)
        #expect(graph.transitions.count == 2)
        #expect(graph.transitions.values.reduce(0) { $0 + $1.count } == 1)
        try GeneratedFunctionStateModel.render().tlaBundle.validateDeclaredClosure()
    }
}
