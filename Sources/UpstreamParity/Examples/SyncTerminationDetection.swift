import SwiftTLA
import SwiftTLAMacros

/// The three-node bounded termination detector from EWD 840.
@TLAModel
package struct SyncTerminationDetectionModel: Sendable {
    package enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case zero = 0
        case one = 1
        case two = 2

        package static var defaultValue: Self { .zero }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .int(rawValue) }
    }

    package static var spec: TLASpec {
        #spec("SyncTerminationDetection") { scope in
            Extends(.integers)
            let active = scope.sharedVar("active", in: SetExpr<Function<Node, Bool>>.literal(
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, false), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, false), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, true), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, true), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, false), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, false), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, true), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, true), (Node.two, true))
            ))
            let terminationDetected = scope.sharedVar("terminationDetected", initial: false)

            SwiftTLA.Action("Terminate_0") {
                active[.zero] == true && active.becomes(active.updating(.zero, to: false)) && terminationDetected.stays
            }
            SwiftTLA.Action("Terminate_1") {
                active[.one] == true && active.becomes(active.updating(.one, to: false)) && terminationDetected.stays
            }
            SwiftTLA.Action("Terminate_2") {
                active[.two] == true && active.becomes(active.updating(.two, to: false)) && terminationDetected.stays
            }
            SwiftTLA.Action("Wakeup_0_to_1") {
                active[.zero] == true && active.becomes(active.updating(.one, to: true)) && terminationDetected.stays
            }
            SwiftTLA.Action("Wakeup_0_to_2") {
                active[.zero] == true && active.becomes(active.updating(.two, to: true)) && terminationDetected.stays
            }
            SwiftTLA.Action("Wakeup_1_to_0") {
                active[.one] == true && active.becomes(active.updating(.zero, to: true)) && terminationDetected.stays
            }
            SwiftTLA.Action("Wakeup_1_to_2") {
                active[.one] == true && active.becomes(active.updating(.two, to: true)) && terminationDetected.stays
            }
            SwiftTLA.Action("Wakeup_2_to_0") {
                active[.two] == true && active.becomes(active.updating(.zero, to: true)) && terminationDetected.stays
            }
            SwiftTLA.Action("Wakeup_2_to_1") {
                active[.two] == true && active.becomes(active.updating(.one, to: true)) && terminationDetected.stays
            }
            SwiftTLA.Action("DetectTermination") {
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
    package static let syncTD = Entry(
        id: "ewd840/SyncTerminationDetection",
        upstreamSpec: "ewd840",
        upstreamModule: "specifications/ewd840/SyncTerminationDetection.tla",
        upstreamCfg: "specifications/ewd840/SyncTerminationDetection.cfg",
        expectedDistinct: 9,
        maximumStateLimit: 50_000,
        spec: SyncTerminationDetectionModel.spec,
        notes: "Three-node abstract termination detection, using typed finite functions. TLC = 9."
    )
}
