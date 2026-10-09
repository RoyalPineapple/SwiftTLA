import Testing
import SwiftTLA
@testable import UpstreamParity

struct EWD998ChanCorpusExecutionTests {
    @Test("trace initialization retains every token position with active white nodes")
    func traceInitialStates() throws {
        let initial = try EWD998ChanModel.initialMachines(
            configuration: .init(N: 5, TraceMode: true))
        #expect(initial.count == 5)
        var tokenPositions = Set<Int>()
        for machine in initial {
            #expect(machine.state.active == [0: true, 1: true, 2: true, 3: true, 4: true])
            #expect(machine.state.color == [0: .white, 1: .white, 2: .white, 3: .white, 4: .white])
            #expect(machine.state.counter == [0: 0, 1: 0, 2: 0, 3: 0, 4: 0])
            let occupied = machine.state.inbox.filter { !$0.value.isEmpty }
            let tokenPosition = try #require(occupied.keys.first)
            #expect(occupied.count == 1)
            #expect(occupied[tokenPosition] == [
                .first(.init(type: .token, q: 0, color: .black))
            ])
            tokenPositions.insert(tokenPosition)
        }
        #expect(tokenPositions == [0, 1, 2, 3, 4])
    }

    @Test("channel delivery preserves token and payload order when a payload is consumed")
    func orderedInboxTransitions() throws {
        let initial = try EWD998ChanModel.initialMachines(configuration: .init(N: 2, TraceMode: false))
        #expect(initial.count == 32)
        let source = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false
                && $0.state.inbox[1]?.count == 1
        })
        let sent = try #require(source.successors().first { $0.action == .SendMsg(sender: 0) }).machine
        #expect(sent.state.inbox[1] == [
            .first(.init(type: .token, q: 0, color: .black)),
            .second(.init(type: .payload))
        ])
        let received = try #require(sent.successors().first { $0.action == .RecvMsg(node: 1) }).machine
        #expect(received.state.inbox[1] == [.first(.init(type: .token, q: 0, color: .black))])
        #expect(received.state.counter[1] == -1)
        let passed = try #require(source.successors().first { $0.action == .PassToken(node: 1) }).machine
        #expect(passed.state.inbox[0] == [.first(.init(type: .token, q: 0, color: .black))])
        #expect(passed.state.inbox[1] == [])
    }

    @Test("the published channel scenario retains its refinement and shared system fairness")
    func publishedConfiguration() throws {
        let scenario = try #require(EWD998ChanModel.validationScenarios().first)
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["TypeOK", "EWD998Spec"])
        #expect(!rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg.contains("N = 3"))
        #expect(rendered.tlaBundle.cfg.contains("TraceMode = FALSE"))
        let machine = try #require(EWD998ChanModel.initialMachines(
            configuration: .init(N: 2, TraceMode: false)).first)
        let conditions = try machine.fairnessConditions()
        #expect(conditions.count == 1)
        #expect(conditions[0].matches(.InitiateProbe))
        #expect(conditions[0].matches(.PassToken(node: 1)))
        #expect(!conditions[0].matches(.SendMsg(sender: 0)))
    }
}
