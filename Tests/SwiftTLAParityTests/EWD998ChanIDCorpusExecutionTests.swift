import Testing
import SwiftTLA
@testable import UpstreamParity

struct EWD998ChanIDCorpusExecutionTests {
    @Test("identifier nodes refine the channel model through indexed node and message projections")
    func channelRefinementMapping() throws {
        let rendered = try EWD998ChanIDModel.render(configuration: .init(Node: [.n1, .n2, .n3]))
        let module = rendered.tlaBundle.root.tla
        #expect(module.contains("EWD998ChanSpec =="))
        #expect(module.contains("inbox <-"))
        #expect(module.contains("counter <-"))
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
