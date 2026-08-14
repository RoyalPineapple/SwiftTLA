import AVFoundation
import SwiftTLA
import SwiftTLAMacros

/// The pipeline contract is a generated model. Capture, writing, and playback
/// are explicit formal stages; AVFoundation remains a thin effect layer.
@TLAModel
public struct MediaPipelineModel {
    public enum Stage: String, CaseIterable, FiniteDomainKey {
        case idle, capturing, writing, readyToPlay, playing
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.pipeline-stage")
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Process: String, FiniteDomainKey { case pipelineEvent
        static let formalDomain: [Self] = [.pipelineEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.pipeline-process")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, PlusCalLabel { case beginCapture, beginWriting, finishWriting, play, stop }
    public static var spec: TLASpec {
        #spec("MediaPipelineModel") {
            Algorithm("MediaPipelineModel") {
                let stage = SharedVar(initial: Stage.idle)
                Each(Process.all) { _ in
                    Do(Step.beginCapture) { When(stage == .idle); Assign(stage, to: Stage.capturing); Goto(Step.beginCapture) }
                    Do(Step.beginWriting) { When(stage == .capturing); Assign(stage, to: Stage.writing); Goto(Step.beginWriting) }
                    Do(Step.finishWriting) { When(stage == .writing); Assign(stage, to: Stage.readyToPlay); Goto(Step.finishWriting) }
                    Do(Step.play) { When(stage == .readyToPlay); Assign(stage, to: Stage.playing); Goto(Step.play) }
                    Do(Step.stop) { When(stage == .capturing || stage == .writing || stage == .playing); Assign(stage, to: Stage.idle); Goto(Step.stop) }
                }
                Invariant("knownPipelineStage") { stage == .idle || stage == .capturing || stage == .writing || stage == .readyToPlay || stage == .playing }
            }
        }
    }
    @TLAActor public actor Machine {}
}

public actor MediaContract {
    private let machine = MediaPipelineModel.Machine()
    public let capture = Media.Capture()
    public let writer: Media.Writer
    public let player: Media.Player
    public init(outputURL: URL) {
        writer = Media.Writer(url: outputURL, fileType: .mp4, outputSettings: [:])
        player = Media.Player(url: outputURL)
    }
    public func stage() async -> MediaPipelineModel.Stage { await machine.state.stage }
}
