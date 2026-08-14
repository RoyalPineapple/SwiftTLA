import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PeripheralSession {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case disconnected
        case connected
        case discovering
        case ready

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.peripheral-session.phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Event: String, CaseIterable, FiniteDomainKey {
        case connected
        case beginDiscovery
        case finishDiscovery
        case disconnected

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.apple.peripheral-session.event")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public struct SessionFields {
        public let phase: Phase
        public let servicesDiscovered: Bool
    }

    public enum SessionSchema: TLARecordSchema {
        public typealias Fields = SessionFields

        public static let fieldNames: Set<String> = ["phase", "servicesDiscovered"]
        public static let defaultRecord: TLAValue = .record([
            "phase": .string(Phase.disconnected.rawValue),
            "servicesDiscovered": .bool(false)
        ])

        public static func fieldName<Value>(for field: KeyPath<SessionFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \SessionFields.phase { return "phase" }
            if key == \SessionFields.servicesDiscovered { return "servicesDiscovered" }
            return nil
        }

        public static let phase = field(\SessionFields.phase)
        public static let servicesDiscovered = field(\SessionFields.servicesDiscovered)
    }

    private enum Step: String, PlusCalLabel {
        case transition
    }

    public static var spec: TLASpec {
        #spec("PeripheralSession") {
            Algorithm("PeripheralSession") {
                let session = SharedVar(initial: Record<SessionSchema>.literal(
                    .init(SessionSchema.phase, Phase.disconnected),
                    .init(SessionSchema.servicesDiscovered, false)
                ))

                Each(Event.all, fairness: .weak) { event in
                    Do(Step.transition) {
                        Either {
                            When(event == .connected)
                            When(session[SessionSchema.phase] == .disconnected)
                            Assign(session, to: Record<SessionSchema>.literal(
                                .init(SessionSchema.phase, Phase.connected),
                                .init(SessionSchema.servicesDiscovered, false)
                            ))
                        } or: {
                            Either {
                                When(event == .beginDiscovery)
                                When(session[SessionSchema.phase] == .connected)
                                Assign(session, to: Record<SessionSchema>.literal(
                                    .init(SessionSchema.phase, Phase.discovering),
                                    .init(SessionSchema.servicesDiscovered, false)
                                ))
                            } or: {
                                Either {
                                    When(event == .finishDiscovery)
                                    When(session[SessionSchema.phase] == .discovering)
                                    Assign(session, to: Record<SessionSchema>.literal(
                                        .init(SessionSchema.phase, Phase.ready),
                                        .init(SessionSchema.servicesDiscovered, true)
                                    ))
                                } or: {
                                    When(event == .disconnected)
                                    When(session[SessionSchema.phase] == .ready)
                                    Assign(session, to: Record<SessionSchema>.literal(
                                        .init(SessionSchema.phase, Phase.disconnected),
                                        .init(SessionSchema.servicesDiscovered, false)
                                    ))
                                }
                            }
                        }
                        Goto(Step.transition)
                    }
                }

                Invariant("ReadyImpliesDiscovered") {
                    session[SessionSchema.phase] != Phase.ready || session[SessionSchema.servicesDiscovered] == true
                }
            }
        }
    }

    @TLAActor
    public actor Runtime {}
}
