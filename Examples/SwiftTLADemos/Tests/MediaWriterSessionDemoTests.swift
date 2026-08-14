import Testing
@testable import SwiftTLADemos

struct MediaWriterSessionDemoTests {
    @Test("writer state comes from generated typed transitions")
    func writerTransitions() throws {
        var machine = MediaWriterSession()
        try MediaWriterSession.verifySpec(); try MediaWriterSession.verifyTransitions(); try MediaWriterSession.verifyInvariants()
        _ = try machine.apply(.transition(process: .configure))
        _ = try machine.apply(.transition(process: .start))
        _ = try machine.apply(.transition(process: .pause))
        #expect(machine.state.phase == .paused)
        _ = try machine.apply(.transition(process: .finish))
        #expect(machine.state.phase == .finished)
    }
}
