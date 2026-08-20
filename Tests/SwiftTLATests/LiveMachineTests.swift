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
        let live = try LiveCounter.makeLive()

        let outcome = try await live.execute(.advance)
        guard case .committed(let transition) = outcome else {
            Issue.record("Expected advance to commit")
            return
        }
        #expect(transition.before == .init(count: 0))
        #expect(transition.after == .init(count: 1))

        guard case .snapshot(let snapshot) = try await live.current() else {
            Issue.record("Expected an active live machine")
            return
        }
        #expect(snapshot.state == transition.after)
        #expect(snapshot.position == .init(value: 1))
    }

    @Test("A disabled typed action leaves the live state unchanged")
    func typedRejectionPreservesState() async throws {
        let live = try LiveCounter.makeLive()
        _ = try await live.execute(.advance)

        guard case .rejected(let rejection) = try await live.execute(.advance) else {
            Issue.record("Expected a disabled action rejection")
            return
        }
        #expect(rejection.reason == .actionNotEnabled)
        #expect(try LiveCounter.State(projection: rejection.current.state) == .init(count: 1))
    }
}
