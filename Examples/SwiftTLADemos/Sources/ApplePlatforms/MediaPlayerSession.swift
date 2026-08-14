import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct MediaPlayerSession {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case idle, loading, ready, playing, paused, finished

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-player.phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case load, ready, play, pause, seek, finish

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-player.event")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel { case transition }

    public static var spec: TLASpec {
        #spec("MediaPlayerSession") {
            Algorithm("MediaPlayerSession") {
                let phase = SharedVar(initial: Phase.idle)

                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .load)
                            When(phase == .idle)
                            Assign(phase, to: Phase.loading)
                        } or: {
                            Either {
                                When(event == .ready)
                                When(phase == .loading)
                                Assign(phase, to: Phase.ready)
                            } or: {
                                Either {
                                    When(event == .play)
                                    When(phase == .ready || phase == .paused)
                                    Assign(phase, to: Phase.playing)
                                } or: {
                                    Either {
                                        When(event == .pause)
                                        When(phase == .playing)
                                        Assign(phase, to: Phase.paused)
                                    } or: {
                                        Either {
                                            When(event == .seek)
                                            When(phase == .ready || phase == .playing || phase == .paused)
                                        } or: {
                                            When(event == .finish)
                                            When(phase == .playing)
                                            Assign(phase, to: Phase.finished)
                                        }
                                    }
                                }
                            }
                        }
                        Goto(Step.transition)
                    }
                }

                Invariant("ValidPhase") {
                    phase == Phase.idle || phase == Phase.loading || phase == Phase.ready ||
                        phase == Phase.playing || phase == Phase.paused || phase == Phase.finished
                }
            }
        }
    }

    @TLAActor
    public actor Runtime {}

    @TLAObservable
    public final class Observable {}
}
