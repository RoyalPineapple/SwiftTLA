import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct DiskStoreSession {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case unopened, ready

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.disk-store.phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case open, write, delete, clear

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.disk-store.event")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel { case transition }

    public static var spec: TLASpec {
        #spec("DiskStoreSession") {
            Algorithm("DiskStoreSession") {
                let phase = SharedVar(initial: Phase.unopened)

                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .open)
                            When(phase == .unopened)
                            Assign(phase, to: Phase.ready)
                        } or: {
                            When(event == .write || event == .delete || event == .clear)
                            When(phase == .ready)
                        }
                        Goto(Step.transition)
                    }
                }

                Invariant("ValidPhase") { phase == Phase.unopened || phase == Phase.ready }
            }
        }
    }

    @TLAActor
    public actor Runtime {}
}
