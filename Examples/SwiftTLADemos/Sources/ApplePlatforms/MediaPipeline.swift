import SwiftTLA
import SwiftTLAMacros

/// The cross-framework contract for capture, writing, and playback.
@TLAModel
public struct MediaPipeline {
    public enum CapturePhase: String, CaseIterable, FiniteDomainKey {
        case idle, configured, running, interrupted

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-pipeline.capture-phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum WriterPhase: String, CaseIterable, FiniteDomainKey {
        case idle, configured, writing, paused, finished, cancelled

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-pipeline.writer-phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum PlayerPhase: String, CaseIterable, FiniteDomainKey {
        case idle, ready, playing, paused

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-pipeline.player-phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case configureCapture
        case configureWriter
        case startRecording
        case pauseWriting
        case resumeWriting
        case stopRecording
        case preparePlayback
        case play
        case pausePlayback

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-pipeline.event")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public struct PipelineFields {
        public let capture: CapturePhase
        public let writer: WriterPhase
        public let player: PlayerPhase
    }

    public enum PipelineSchema: TLARecordSchema {
        public typealias Fields = PipelineFields

        public static let fieldNames: Set<String> = ["capture", "writer", "player"]
        public static let defaultRecord: TLAValue = .record([
            "capture": .string(CapturePhase.idle.rawValue),
            "writer": .string(WriterPhase.idle.rawValue),
            "player": .string(PlayerPhase.idle.rawValue)
        ])

        public static func fieldName<Value>(for field: KeyPath<PipelineFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \PipelineFields.capture { return "capture" }
            if key == \PipelineFields.writer { return "writer" }
            if key == \PipelineFields.player { return "player" }
            return nil
        }

        public static let capture = field(\PipelineFields.capture)
        public static let writer = field(\PipelineFields.writer)
        public static let player = field(\PipelineFields.player)
    }

    private enum Step: String, PlusCalLabel { case transition }

    public static var spec: TLASpec {
        #spec("MediaPipeline") {
            Algorithm("MediaPipeline") {
                let pipeline = SharedVar(initial: Record<PipelineSchema>.literal(
                    .init(PipelineSchema.capture, CapturePhase.idle),
                    .init(PipelineSchema.writer, WriterPhase.idle),
                    .init(PipelineSchema.player, PlayerPhase.idle)
                ))

                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .configureCapture)
                            When(pipeline[PipelineSchema.capture] == .idle)
                            Assign(pipeline, to: Record<PipelineSchema>.literal(
                                .init(PipelineSchema.capture, CapturePhase.configured),
                                .init(PipelineSchema.writer, pipeline[PipelineSchema.writer]),
                                .init(PipelineSchema.player, pipeline[PipelineSchema.player])
                            ))
                        } or: {
                            Either {
                                When(event == .configureWriter)
                                When(pipeline[PipelineSchema.writer] == .idle)
                                Assign(pipeline, to: Record<PipelineSchema>.literal(
                                    .init(PipelineSchema.capture, pipeline[PipelineSchema.capture]),
                                    .init(PipelineSchema.writer, WriterPhase.configured),
                                    .init(PipelineSchema.player, pipeline[PipelineSchema.player])
                                ))
                            } or: {
                                Either {
                                    When(event == .startRecording)
                                    When(pipeline[PipelineSchema.capture] == .configured)
                                    When(pipeline[PipelineSchema.writer] == .configured)
                                    Assign(pipeline, to: Record<PipelineSchema>.literal(
                                        .init(PipelineSchema.capture, CapturePhase.running),
                                        .init(PipelineSchema.writer, WriterPhase.writing),
                                        .init(PipelineSchema.player, pipeline[PipelineSchema.player])
                                    ))
                                } or: {
                                    Either {
                                        When(event == .pauseWriting)
                                        When(pipeline[PipelineSchema.capture] == .running)
                                        When(pipeline[PipelineSchema.writer] == .writing)
                                        Assign(pipeline, to: Record<PipelineSchema>.literal(
                                            .init(PipelineSchema.capture, pipeline[PipelineSchema.capture]),
                                            .init(PipelineSchema.writer, WriterPhase.paused),
                                            .init(PipelineSchema.player, pipeline[PipelineSchema.player])
                                        ))
                                    } or: {
                                        Either {
                                            When(event == .resumeWriting)
                                            When(pipeline[PipelineSchema.capture] == .running)
                                            When(pipeline[PipelineSchema.writer] == .paused)
                                            Assign(pipeline, to: Record<PipelineSchema>.literal(
                                                .init(PipelineSchema.capture, pipeline[PipelineSchema.capture]),
                                                .init(PipelineSchema.writer, WriterPhase.writing),
                                                .init(PipelineSchema.player, pipeline[PipelineSchema.player])
                                            ))
                                        } or: {
                                            Either {
                                                When(event == .stopRecording)
                                                When(pipeline[PipelineSchema.capture] == .running)
                                                When(pipeline[PipelineSchema.writer] == .writing || pipeline[PipelineSchema.writer] == .paused)
                                                Assign(pipeline, to: Record<PipelineSchema>.literal(
                                                    .init(PipelineSchema.capture, CapturePhase.idle),
                                                    .init(PipelineSchema.writer, WriterPhase.finished),
                                                    .init(PipelineSchema.player, pipeline[PipelineSchema.player])
                                                ))
                                            } or: {
                                                Either {
                                                    When(event == .preparePlayback)
                                                    When(pipeline[PipelineSchema.writer] == .finished)
                                                    When(pipeline[PipelineSchema.player] == .idle)
                                                    Assign(pipeline, to: Record<PipelineSchema>.literal(
                                                        .init(PipelineSchema.capture, pipeline[PipelineSchema.capture]),
                                                        .init(PipelineSchema.writer, pipeline[PipelineSchema.writer]),
                                                        .init(PipelineSchema.player, PlayerPhase.ready)
                                                    ))
                                                } or: {
                                                    Either {
                                                        When(event == .play)
                                                        When(pipeline[PipelineSchema.writer] == .finished)
                                                        When(pipeline[PipelineSchema.player] == .ready || pipeline[PipelineSchema.player] == .paused)
                                                        Assign(pipeline, to: Record<PipelineSchema>.literal(
                                                            .init(PipelineSchema.capture, pipeline[PipelineSchema.capture]),
                                                            .init(PipelineSchema.writer, pipeline[PipelineSchema.writer]),
                                                            .init(PipelineSchema.player, PlayerPhase.playing)
                                                        ))
                                                    } or: {
                                                        When(event == .pausePlayback)
                                                        When(pipeline[PipelineSchema.player] == .playing)
                                                        Assign(pipeline, to: Record<PipelineSchema>.literal(
                                                            .init(PipelineSchema.capture, pipeline[PipelineSchema.capture]),
                                                            .init(PipelineSchema.writer, pipeline[PipelineSchema.writer]),
                                                            .init(PipelineSchema.player, PlayerPhase.paused)
                                                        ))
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Goto(Step.transition)
                    }
                }

                Invariant("WritingRequiresCapture") {
                    pipeline[PipelineSchema.writer] != WriterPhase.writing && pipeline[PipelineSchema.writer] != WriterPhase.paused ||
                        pipeline[PipelineSchema.capture] == CapturePhase.running
                }
                Invariant("PlaybackRequiresFinishedWriter") {
                    pipeline[PipelineSchema.player] != PlayerPhase.playing ||
                        pipeline[PipelineSchema.writer] == WriterPhase.finished
                }
            }
        }
    }

    @TLAActor
    public actor Runtime {}

    @TLAObservable
    public final class Observable {}
}
