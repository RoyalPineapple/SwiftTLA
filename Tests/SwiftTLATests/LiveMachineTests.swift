import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct LiveCounter {
    static var spec: TLASpec {
        TLASpec("LiveCounter") {
            let count = Var<Int>("count")
            Variable(count, 0)
            Action("advance") { count.becomes(count + 1).when(count < 1) }
        }
    }

    @TLAActor
    actor Actor {}
}

@Suite("Live machine")
struct LiveMachineTests {
    @Test("A model creates and executes its typed live machine")
    func typedActionCommitsTypedState() async throws {
        let live = try LiveCounter.Live()
        let transition = try await live.send(.advance)
        #expect(transition.before == .init(count: 0))
        #expect(transition.after == .init(count: 1))

        #expect(await live.state == transition.after)
    }

    @Test("A disabled typed action leaves the live state unchanged")
    func typedRejectionPreservesState() async throws {
        let live = try LiveCounter.Live()
        _ = try await live.send(.advance)

        #expect(throws: GeneratedMachineError.self) {
            try await live.send(.advance)
        }
        #expect(await live.state == .init(count: 1))
    }
}
