import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct RetryPolicy {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case idle, attempting, backingOff, succeeded, failed, cancelled

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.retry.phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case start, succeed, retryableFailure, terminalFailure, retry, cancel

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.retry.event")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel { case transition }
    public static let maximumAttempts = 3

    public static var spec: TLASpec {
        #spec("RetryPolicy") {
            Algorithm("RetryPolicy") {
                let phase = SharedVar(initial: Phase.idle)
                let attempts = SharedVar(initial: 0)

                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .start)
                            When(phase == .idle)
                            When(attempts == 0)
                            Assign(phase, to: Phase.attempting)
                            Assign(attempts, to: 1)
                        } or: {
                            Either {
                                When(event == .succeed)
                                When(phase == .attempting)
                                Assign(phase, to: Phase.succeeded)
                            } or: {
                                Either {
                                    When(event == .retryableFailure)
                                    When(phase == .attempting)
                                    When(attempts < 3)
                                    Assign(phase, to: Phase.backingOff)
                                } or: {
                                    Either {
                                        When(event == .terminalFailure)
                                        When(phase == .attempting)
                                        When(attempts == 3)
                                        Assign(phase, to: Phase.failed)
                                    } or: {
                                        Either {
                                            When(event == .retry)
                                            When(phase == .backingOff)
                                            Assign(phase, to: Phase.attempting)
                                            Assign(attempts, to: attempts + 1)
                                        } or: {
                                            When(event == .cancel)
                                            When(phase == .idle || phase == .attempting || phase == .backingOff)
                                            Assign(phase, to: Phase.cancelled)
                                        }
                                    }
                                }
                            }
                        }
                        Goto(Step.transition)
                    }
                }

                Invariant("BoundedAttempts") { attempts >= 0 && attempts <= 3 }
            }
        }
    }

    @TLAActor
    public actor Runtime {}

    @TLAObservable
    public final class Observable {}
}
