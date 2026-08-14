import Testing
@testable import SwiftTLADemos

struct RetryPolicyDemoTests {
    @Test("retry policy has a bounded generated attempt count")
    func retryTransitions() throws {
        var machine = RetryPolicy()

        try RetryPolicy.verifySpec()
        try RetryPolicy.verifyTransitions()
        try RetryPolicy.verifyInvariants()

        _ = try machine.apply(.transition(process: .start))
        _ = try machine.apply(.transition(process: .retryableFailure))
        _ = try machine.apply(.transition(process: .retry))

        #expect(machine.state.phase == .attempting)
        #expect(machine.state.attempts == 2)
    }
}
