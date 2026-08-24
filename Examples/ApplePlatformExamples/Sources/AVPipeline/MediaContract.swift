import AVFoundation
import SwiftTLA
import SwiftTLAMacros

/// The pipeline contract is a generated model. Capture, writing, and playback
/// are explicit formal stages; AVFoundation remains a thin effect layer.
@TLAModel
public struct MediaPipelineModel {
    public enum Stage: String, CaseIterable, FiniteTLAValueDomain {
        case idle, capturing, writing, readyToPlay, playing
        public static var defaultValue: Self { .idle }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum BeginCaptureProcess: String, FiniteTLAValueDomain { case beginCaptureEvent; static var defaultValue: Self { .beginCaptureEvent }; static let finiteValues: [Self] = [.beginCaptureEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum BeginWritingProcess: String, FiniteTLAValueDomain { case beginWritingEvent; static var defaultValue: Self { .beginWritingEvent }; static let finiteValues: [Self] = [.beginWritingEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum FinishWritingProcess: String, FiniteTLAValueDomain { case finishWritingEvent; static var defaultValue: Self { .finishWritingEvent }; static let finiteValues: [Self] = [.finishWritingEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum PlayProcess: String, FiniteTLAValueDomain { case playEvent; static var defaultValue: Self { .playEvent }; static let finiteValues: [Self] = [.playEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum StopProcess: String, FiniteTLAValueDomain { case stopEvent; static var defaultValue: Self { .stopEvent }; static let finiteValues: [Self] = [.stopEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum Step: String, CaseIterable { case beginCapture, beginWriting, finishWriting, play, stop }
    public static var spec: TLASpec {
        #spec("MediaPipelineModel") {
            Algorithm("MediaPipelineModel", scoped: { scope in
                let stage = scope.sharedVar("stage", initial: Stage.idle)
                Each(BeginCaptureProcess.all) { _ in Do(Step.beginCapture) { When(stage == .idle); Assign(stage, to: Stage.capturing); Goto(Step.beginCapture) } }
                Each(BeginWritingProcess.all) { _ in Do(Step.beginWriting) { When(stage == .capturing); Assign(stage, to: Stage.writing); Goto(Step.beginWriting) } }
                Each(FinishWritingProcess.all) { _ in Do(Step.finishWriting) { When(stage == .writing); Assign(stage, to: Stage.readyToPlay); Goto(Step.finishWriting) } }
                Each(PlayProcess.all) { _ in Do(Step.play) { When(stage == .readyToPlay); Assign(stage, to: Stage.playing); Goto(Step.play) } }
                Each(StopProcess.all) { _ in Do(Step.stop) { When(stage == .capturing || stage == .writing || stage == .playing); Assign(stage, to: Stage.idle); Goto(Step.stop) } }
                Invariant("knownPipelineStage") { stage == .idle || stage == .capturing || stage == .writing || stage == .readyToPlay || stage == .playing }
            })
        }
    }
}

public actor MediaContract {
    private var machine: MediaPipelineModel
    public let capture: Media.Capture
    public let writer: Media.Writer
    public let player: Media.Player

    public init(outputURL: URL) throws {
        machine = try MediaPipelineModel.makeMachine()
        capture = try Media.Capture()
        writer = try Media.Writer(url: outputURL, fileType: .mp4, outputSettings: [:])
        player = try Media.Player(url: outputURL)
    }

    public func stage() async -> MediaPipelineModel.Stage { machine.state.stage }
}
