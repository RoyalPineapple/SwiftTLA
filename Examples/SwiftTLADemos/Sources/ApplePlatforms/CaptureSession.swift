import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct CaptureSession {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case idle, configured, running, interrupted

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.capture-session.phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case configure, start, stop, interrupt, resume

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.capture-session.event")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel { case transition }

    public static var spec: TLASpec {
        #spec("CaptureSession") {
            Algorithm("CaptureSession") {
                let phase = SharedVar(initial: Phase.idle)

                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .configure)
                            When(phase == .idle)
                            Assign(phase, to: Phase.configured)
                        } or: {
                            Either {
                                When(event == .start)
                                When(phase == .configured)
                                Assign(phase, to: Phase.running)
                            } or: {
                                Either {
                                    When(event == .stop)
                                    When(phase == .running || phase == .interrupted)
                                    Assign(phase, to: Phase.idle)
                                } or: {
                                    Either {
                                        When(event == .interrupt)
                                        When(phase == .running)
                                        Assign(phase, to: Phase.interrupted)
                                    } or: {
                                        When(event == .resume)
                                        When(phase == .interrupted)
                                        Assign(phase, to: Phase.running)
                                    }
                                }
                            }
                        }
                        Goto(Step.transition)
                    }
                }

                Invariant("ValidPhase") {
                    phase == Phase.idle || phase == Phase.configured || phase == Phase.running || phase == Phase.interrupted
                }
            }
        }
    }

    @TLAActor
    public actor Runtime {}

    @TLAObservable
    public final class Observable {}
}
