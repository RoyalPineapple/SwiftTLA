import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct AdapterCounter {
    static var spec: TLASpec {
        TLASpec("AdapterCounter") {
            let count = Var<Int>("count")
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 1) }
        }
    }

    @TLAActor
    actor Actor {}

}

@Suite("Generated live machines")
struct LiveMachineAdapterTests {
    @Test("Actor delegates to the generated live machine")
    func actorDelegatesToGeneratedLiveMachine() async throws {
        let actor = try AdapterCounter.Actor()
        let transition = try await actor.send(.advance)

        #expect(transition.after == .init(count: 1))
        #expect(await actor.state == transition.after)
    }
}
