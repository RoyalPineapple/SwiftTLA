import SwiftTLA
import SwiftTLAMacros

/// The three-node bounded termination detector from EWD 840.
@TLAModel
public struct SyncTerminationDetectionModel: Sendable {
    public enum Node: Int, CaseIterable, FiniteDomainKey {
        case zero = 0
        case one = 1
        case two = 2

        public static var defaultValue: Self { .zero }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.sync-termination.node")
        public var tlaValue: TLAValue { .int(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("SyncTerminationDetection") {
            Extends(.integers)
            let active = SharedVar("active", in: SetExpr<Function<Node, Bool>>.literal(
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, false), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, false), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, true), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, true), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, false), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, false), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, true), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, true), (Node.two, true))
            ))
            let terminationDetected = SharedVar("terminationDetected", initial: false)

            Action("Terminate_0") {
                active[.zero] == true && active.becomes(active.updating(.zero, to: false)) && terminationDetected.stays
            }
            Action("Terminate_1") {
                active[.one] == true && active.becomes(active.updating(.one, to: false)) && terminationDetected.stays
            }
            Action("Terminate_2") {
                active[.two] == true && active.becomes(active.updating(.two, to: false)) && terminationDetected.stays
            }
            Action("Wakeup_0_to_1") {
                active[.zero] == true && active.becomes(active.updating(.one, to: true)) && terminationDetected.stays
            }
            Action("Wakeup_0_to_2") {
                active[.zero] == true && active.becomes(active.updating(.two, to: true)) && terminationDetected.stays
            }
            Action("Wakeup_1_to_0") {
                active[.one] == true && active.becomes(active.updating(.zero, to: true)) && terminationDetected.stays
            }
            Action("Wakeup_1_to_2") {
                active[.one] == true && active.becomes(active.updating(.two, to: true)) && terminationDetected.stays
            }
            Action("Wakeup_2_to_0") {
                active[.two] == true && active.becomes(active.updating(.zero, to: true)) && terminationDetected.stays
            }
            Action("Wakeup_2_to_1") {
                active[.two] == true && active.becomes(active.updating(.one, to: true)) && terminationDetected.stays
            }
            Action("DetectTermination") {
                active[.zero] == false && active[.one] == false && active[.two] == false
                    && terminationDetected.becomes(true) && active.stays
            }
            Invariant("TDCorrect") {
                terminationDetected == false || (active[.zero] == false && active[.one] == false && active[.two] == false)
            }
        }
    }
}

extension Example {
    public static let syncTD = Entry(
        id: "ewd840/SyncTerminationDetection",
        upstreamSpec: "ewd840",
        upstreamModule: "specifications/ewd840/SyncTerminationDetection.tla",
        upstreamCfg: "specifications/ewd840/SyncTerminationDetection.cfg",
        expectedDistinct: 9,
        spec: SyncTerminationDetectionModel.spec,
        notes: "Three-node abstract termination detection, using typed finite functions. TLC = 9."
    )
}
