import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct BluetoothCentral {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case unknown
        case resetting
        case unsupported
        case unauthorized
        case poweredOff
        case poweredOn
        case scanning

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.bluetooth-central.phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case poweredOn
        case poweredOff
        case unsupported
        case unauthorized
        case resetting
        case startScan
        case stopScan

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.bluetooth-central.event")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case transition
    }

    public static var spec: TLASpec {
        #spec("BluetoothCentral") {
            Algorithm("BluetoothCentral") {
                let phase = SharedVar(initial: Phase.unknown)

                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .poweredOn)
                            When(phase == .unknown || phase == .resetting || phase == .poweredOff)
                            Assign(phase, to: Phase.poweredOn)
                        } or: {
                            Either {
                                When(event == .poweredOff)
                                When(phase == .unknown || phase == .resetting || phase == .poweredOn)
                                Assign(phase, to: Phase.poweredOff)
                            } or: {
                                Either {
                                    When(event == .unsupported)
                                    When(phase == .unknown)
                                    Assign(phase, to: Phase.unsupported)
                                } or: {
                                    Either {
                                        When(event == .unauthorized)
                                        When(phase == .unknown)
                                        Assign(phase, to: Phase.unauthorized)
                                    } or: {
                                        Either {
                                            When(event == .resetting)
                                            When(phase == .poweredOff || phase == .poweredOn)
                                            Assign(phase, to: Phase.resetting)
                                        } or: {
                                            Either {
                                                When(event == .startScan)
                                                When(phase == .poweredOn)
                                                Assign(phase, to: Phase.scanning)
                                            } or: {
                                                When(event == .stopScan)
                                                When(phase == .scanning)
                                                Assign(phase, to: Phase.poweredOn)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Goto(Step.transition)
                    }
                }

                Invariant("ValidPhase") {
                    phase == .unknown || phase == .resetting || phase == .unsupported
                        || phase == .unauthorized || phase == .poweredOff || phase == .poweredOn
                        || phase == .scanning
                }
            }
        }
    }

    @TLAActor
    public actor Runtime {}

    @TLAObservable
    public final class Observable {}
}
