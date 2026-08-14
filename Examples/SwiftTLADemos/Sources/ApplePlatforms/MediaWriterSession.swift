import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct MediaWriterSession {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case idle, configured, writing, paused, finished, cancelled
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-writer.phase")
        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case configure, start, pause, resume, finish, cancel
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.media-writer.event")
        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel { case transition }

    public static var spec: TLASpec {
        #spec("MediaWriterSession") {
            Algorithm("MediaWriterSession") {
                let phase = SharedVar(initial: Phase.idle)
                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .configure); When(phase == .idle); Assign(phase, to: Phase.configured)
                        } or: {
                            Either {
                                When(event == .start); When(phase == .configured); Assign(phase, to: Phase.writing)
                            } or: {
                                Either {
                                    When(event == .pause); When(phase == .writing); Assign(phase, to: Phase.paused)
                                } or: {
                                    Either {
                                        When(event == .resume); When(phase == .paused); Assign(phase, to: Phase.writing)
                                    } or: {
                                        Either {
                                            When(event == .finish); When(phase == .configured || phase == .writing || phase == .paused); Assign(phase, to: Phase.finished)
                                        } or: {
                                            When(event == .cancel); When(phase == .writing || phase == .paused); Assign(phase, to: Phase.cancelled)
                                        }
                                    }
                                }
                            }
                        }
                        Goto(Step.transition)
                    }
                }
                Invariant("ValidPhase") { phase == Phase.idle || phase == Phase.configured || phase == Phase.writing || phase == Phase.paused || phase == Phase.finished || phase == Phase.cancelled }
            }
        }
    }

    @TLAActor public actor Runtime {}
    @TLAObservable public final class Observable {}
}
