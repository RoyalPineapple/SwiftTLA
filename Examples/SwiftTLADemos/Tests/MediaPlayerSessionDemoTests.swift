import Testing
@testable import SwiftTLADemos

struct MediaPlayerSessionDemoTests {
    @Test("player state comes from generated typed transitions")
    func playerTransitions() throws {
        var machine = MediaPlayerSession()

        try MediaPlayerSession.verifySpec()
        try MediaPlayerSession.verifyTransitions()
        try MediaPlayerSession.verifyInvariants()

        _ = try machine.apply(.transition(process: .load))
        _ = try machine.apply(.transition(process: .ready))
        _ = try machine.apply(.transition(process: .play))
        _ = try machine.apply(.transition(process: .pause))

        #expect(machine.state.phase == .paused)
    }
}
