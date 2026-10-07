import Testing
import SwiftTLA
@testable import UpstreamParity

struct EWD998CorpusExecutionTests {
    @Test("Safra's token and counters retain the published send, receive, and pass effects")
    func generatedTransitions() throws {
        let initial = try EWD998Model.initialMachines(configuration: .init(N: 2))
        #expect(initial.count == 32)
        let source = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false
                && $0.state.token.pos == 1
        })
        let sent = try #require(source.successors().first { $0.action == .SendMsg(sender: 0) }).machine
        #expect(sent.state.counter[0] == 1)
        #expect(sent.state.pending[1] == 1)
        let received = try #require(sent.successors().first { $0.action == .RecvMsg(node: 1) }).machine
        #expect(received.state.pending[1] == 0)
        #expect(received.state.counter[1] == -1)
        #expect(received.state.color[1] == .black)
        #expect(received.state.active[1] == true)
        let passed = try #require(source.successors().first { $0.action == .PassToken(node: 1) }).machine
        #expect(passed.state.token.pos == 0)
        #expect(passed.state.token.q == 0)
    }

    @Test("the published four- and three-node scenarios select different checks without changing the model")
    func publishedConfigurations() throws {
        let scenarios = try EWD998Model.validationScenarios()
        let full = try #require(scenarios.first { $0.name == "EWD998" })
        let small = try #require(scenarios.first { $0.name == "EWD998Small" })
        let fullOutput = try full.render()
        let smallOutput = try small.render()
        #expect(fullOutput.checkNames == ["TypeOK", "TerminationDetection", "Inv", "Liveness", "TDSpec"])
        #expect(smallOutput.checkNames == ["TypeOK", "TerminationDetection", "Inv"])
        #expect(!fullOutput.checksDeadlock && !smallOutput.checksDeadlock)
        #expect(fullOutput.tlaBundle.cfg.contains("N = 4"))
        #expect(smallOutput.tlaBundle.cfg.contains("N = 3"))
        #expect(fullOutput.tlaBundle.tla == smallOutput.tlaBundle.tla)
        #expect(fullOutput.tlaBundle.imports.contains { $0.name == "Functions" })
    }

    @Test("Safra's system actions share one weak-fairness obligation")
    func systemFairness() throws {
        let machine = try #require(EWD998Model.initialMachines(configuration: .init(N: 2)).first)
        let conditions = try machine.fairnessConditions()
        #expect(conditions.count == 1)
        #expect(conditions[0].matches(.InitiateProbe))
        #expect(conditions[0].matches(.PassToken(node: 1)))
        #expect(!conditions[0].matches(.SendMsg(sender: 0)))

        let rendered = try EWD998Model.render(configuration: .init(N: 2))
        let obligations = rendered.tlaBundle.root.tla.split(separator: "\n").filter { $0.contains("WF_") }
        #expect(obligations.count == 1)
        #expect(obligations[0].contains("InitiateProbe"))
        #expect(obligations[0].contains("PassToken"))
        #expect(obligations[0].contains("\\/"))
    }
}
