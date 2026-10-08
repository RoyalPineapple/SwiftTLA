import Testing
import SwiftTLA
@testable import UpstreamParity

struct EWD998PCalCorpusExecutionTests {
    @Test("the generated process preserves bag multiplicity and moves the token")
    func bagAndTokenTransitions() throws {
        let initial = try EWD998PCalModel.initialMachines(configuration: .init(N: 2))
        #expect(initial.count == 4)
        let source = try #require(initial.first {
            $0.state.active[0] == true && $0.state.active[1] == false
        })
        let payload = EWD998PCalModel.Message.second(.init(type: .payload))
        let blackToken = EWD998PCalModel.Message.first(.init(type: .token, q: 0, color: .black))
        let whiteToken = EWD998PCalModel.Message.first(.init(type: .token, q: 0, color: .white))
        #expect(source.state.network[0]?[blackToken] == 1)
        #expect(source.state.network[1]?.isEmpty == true)

        let firstSend = try #require(source.successors().first {
            $0.action == .node(process: 0) && $0.machine.state.network[1]?[payload] == 1
        }).machine
        let secondSend = try #require(firstSend.successors().first {
            $0.action == .node(process: 0) && $0.machine.state.network[1]?[payload] == 2
        }).machine
        #expect(secondSend.state.counter[0] == 2)

        let initiated = try #require(source.successors().first {
            $0.action == .node(process: 0) && $0.machine.state.network[1]?[whiteToken] == 1
        }).machine
        #expect(initiated.state.network[0]?[blackToken] == nil)
        let passed = try #require(initiated.successors().first {
            $0.action == .node(process: 1) && $0.machine.state.network[0]?[blackToken] == 1
        }).machine
        #expect(passed.state.network[1]?[whiteToken] == nil)
    }

    @Test("the published PlusCal configuration checks abstract safety with default deadlock")
    func publishedConfiguration() throws {
        let scenario = try #require(EWD998PCalModel.validationScenarios().first)
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["EWD998Spec"])
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.cfg.contains("N = 3"))
        #expect(rendered.tlaBundle.cfg.contains("CONSTRAINT StateConstraint"))
        #expect(rendered.tlaBundle.tla.contains("node("))
        #expect(rendered.tlaBundle.root.tla.contains("EWD998Spec == abstract!Init /\\ [][abstract!Next]_abstract!vars"))
    }
}
