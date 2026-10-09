import Testing
import SwiftTLA
@testable import UpstreamParity

struct EWD998ChanIDCorpusExecutionTests {
    @Test("published identifier-node configuration selects the clock-free view and all checks")
    func publishedViewConfiguration() throws {
        let scenario = try #require(EWD998ChanIDModel.validationScenarios().first)
        let rendered = try scenario.render()
        let cfg = rendered.tlaBundle.cfg
        let module = rendered.tlaBundle.root.tla

        #expect(scenario.name == "EWD998ChanID")
        #expect(scenario.usesView)
        #expect(cfg.contains("VIEW __SwiftTLAView"))
        #expect(cfg.contains("CHECK_DEADLOCK FALSE"))
        #expect(cfg.contains("EWD998Safe"))
        #expect(cfg.contains("Max3TokenRounds"))
        #expect(cfg.contains("EWD998ChanSpec"))
        #expect(cfg.contains("EWD998Live"))
        #expect(module.contains("__SwiftTLAView"))
        #expect(!module.contains("__SwiftTLAView == clock"))
    }

    @Test("identifier-node refinement renders for three and seven-node configurations")
    func channelRefinementMapping() throws {
        let rendered = try EWD998ChanIDModel.render(configuration: .init(Node: [.n1, .n2, .n3]))
        let module = rendered.tlaBundle.root.tla
        #expect(module.contains("EWD998ChanSpec =="))
        #expect(module.contains("inbox <-"))
        #expect(module.contains("counter <-"))

        let sevenNodes = try EWD998ChanIDModel.render(configuration: .init(Node: Set(EWD998ChanIDModel.NodeID.allCases)))
        #expect(sevenNodes.tlaBundle.cfg.contains("n7"))
    }

    @Test("the initial token carries its node clock and passing it advances that clock")
    func initialTokenPass() throws {
        let nodes: Set<EWD998ChanIDModel.NodeID> = [.n1, .n2, .n3]
        let initial = try EWD998ChanIDModel.initialMachines(configuration: .init(Node: nodes))
        let machine = try #require(initial.first)
        let owner = try #require(nodes.first { machine.state.inbox[$0]?.count == 1 })
        let message = try #require(machine.state.inbox[owner]?.first)
        guard case .first(let token) = message else {
            Issue.record("The initial message must be the token.")
            return
        }
        #expect(token.vc == machine.state.clock[owner])
        #expect(machine.state.passes == 0)
        let previousClock = try #require(machine.state.clock[owner]?[owner])

        let passed = try #require(machine.successors().first {
            $0.action == .PassToken(node: owner)
        }).machine
        #expect(passed.state.clock[owner]?[owner] == previousClock + 1)
        #expect(passed.state.inbox[owner] == [])
        #expect(passed.state.passes == 1)
        let forwardedMessages = nodes.compactMap { passed.state.inbox[$0]?.first }
        let forwarded = try #require(forwardedMessages.first)
        guard case .first(let forwardedToken) = forwarded else {
            Issue.record("The forwarded message must be the token.")
            return
        }
        #expect(forwardedToken.vc == passed.state.clock[owner])
    }
}
