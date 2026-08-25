import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct CameraWorkflow {
    public enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case starting, live, recording, stopping, playing

        public static var defaultValue: Self { .starting }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum ReadyProcess: String, FiniteTLAValueDomain { case readyEvent
        static var defaultValue: Self { .readyEvent }
        static let finiteValues: [Self] = [.readyEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum RecordProcess: String, FiniteTLAValueDomain { case recordEvent
        static var defaultValue: Self { .recordEvent }
        static let finiteValues: [Self] = [.recordEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum StopRecordingProcess: String, FiniteTLAValueDomain { case stopRecordingEvent
        static var defaultValue: Self { .stopRecordingEvent }
        static let finiteValues: [Self] = [.stopRecordingEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum RecordingSucceededProcess: String, FiniteTLAValueDomain { case recordingSucceededEvent
        static var defaultValue: Self { .recordingSucceededEvent }
        static let finiteValues: [Self] = [.recordingSucceededEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum RecordingFailedProcess: String, FiniteTLAValueDomain { case recordingFailedEvent
        static var defaultValue: Self { .recordingFailedEvent }
        static let finiteValues: [Self] = [.recordingFailedEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum PlayProcess: String, FiniteTLAValueDomain { case playEvent
        static var defaultValue: Self { .playEvent }
        static let finiteValues: [Self] = [.playEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum LiveProcess: String, FiniteTLAValueDomain { case liveEvent
        static var defaultValue: Self { .liveEvent }
        static let finiteValues: [Self] = [.liveEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, CaseIterable { case ready, record, stopRecording, recordingSucceeded, recordingFailed, play, live }

    public static var spec: TLASpec {
        #spec("CameraWorkflow") {
            Algorithm("CameraWorkflow", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.starting)
                Each(ReadyProcess.all) { _ in
                    Do(Step.ready) { When(phase == Phase.starting); Assign(phase, to: Phase.live); Goto(Step.ready) }
                }
                Each(RecordProcess.all) { _ in
                    Do(Step.record) { When(phase == Phase.live); Assign(phase, to: Phase.recording); Goto(Step.record) }
                }
                Each(StopRecordingProcess.all) { _ in
                    Do(Step.stopRecording) { When(phase == Phase.recording); Assign(phase, to: Phase.stopping); Goto(Step.stopRecording) }
                }
                Each(RecordingSucceededProcess.all) { _ in
                    Do(Step.recordingSucceeded) { When(phase == Phase.stopping); Assign(phase, to: Phase.live); Goto(Step.recordingSucceeded) }
                }
                Each(RecordingFailedProcess.all) { _ in
                    Do(Step.recordingFailed) { When(phase == Phase.recording || phase == Phase.stopping); Assign(phase, to: Phase.live); Goto(Step.recordingFailed) }
                }
                Each(PlayProcess.all) { _ in
                    Do(Step.play) { When(phase == Phase.live); Assign(phase, to: Phase.playing); Goto(Step.play) }
                }
                Each(LiveProcess.all) { _ in
                    Do(Step.live) { When(phase == Phase.playing); Assign(phase, to: Phase.live); Goto(Step.live) }
                }
                Invariant("validPhase") { phase == Phase.starting || phase == Phase.live || phase == Phase.recording || phase == Phase.stopping || phase == Phase.playing }
            })
        }
    }
}
