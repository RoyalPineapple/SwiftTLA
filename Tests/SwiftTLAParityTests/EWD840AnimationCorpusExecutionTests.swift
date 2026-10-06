import Testing
import SwiftTLA
import UpstreamParity

struct EWD840AnimationCorpusExecutionTests {
    @Test("animated steps preserve typed history and render the level check")
    func generatedHistoryAndCheck() throws {
        let configuration = try EWD840AnimationModel.Configuration(N: 2)
        let initial = try EWD840AnimationModel.initialMachines(configuration: configuration)
        #expect(initial.count == 16)
        var machine = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false
        })
        #expect(machine.state.tpos == 1)
        #expect(machine.state.history == Triple(first: 0, second: 0, third: "init"))

        _ = try machine.send(.AnimSendMsg(i: 0))
        #expect(machine.state.active[1] == true)
        #expect(machine.state.color[0] == .black)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "SendMsg"))

        _ = try machine.send(.AnimDeactivate(i: 1))
        #expect(machine.state.active[1] == false)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "Deactivate"))

        _ = try machine.send(.AnimPassToken(i: 1))
        #expect(machine.state.tpos == 0)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "PassToken"))

        _ = try machine.send(.AnimInitiateProbe)
        #expect(machine.state.tpos == 1)
        #expect(machine.state.history == Triple(first: 0, second: 1, third: "InitiateProbe"))

        let rendered = try EWD840AnimationModel.render(configuration: configuration)
        #expect(rendered.tlaBundle.root.tla.contains("EXTENDS Integers, Naturals, TLC"))
        #expect(rendered.tlaBundle.root.tla.contains("TLCGet(\"level\")"))
        #expect(rendered.checkNames.contains("AnimInv"))
    }
}
