import Testing
@testable import SwiftTLADemos

struct CaptureSessionDemoTests {
    @Test("capture session exposes typed interruption and resume")
    func generatedCaptureTransitions() throws {
        var machine = CaptureSession()
        try CaptureSession.verifySpec()
        try CaptureSession.verifyTransitions()
        try CaptureSession.verifyInvariants()

        _ = try machine.apply(.transition(process: .configure))
        _ = try machine.apply(.transition(process: .start))
        _ = try machine.apply(.transition(process: .interrupt))
        #expect(machine.state.phase == .interrupted)
        _ = try machine.apply(.transition(process: .resume))
        #expect(machine.state.phase == .running)
    }
}
