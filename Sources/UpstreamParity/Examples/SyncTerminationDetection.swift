import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd840/SyncTerminationDetection.tla, SyncTerminationDetection.cfg.
@TLAModel
package struct SyncTerminationDetectionModel: Sendable {
    private enum Step: String, CaseIterable {
        case Terminate, Wakeup, DetectTermination
    }

    package static var spec: TLASpec {
        #spec("SyncTerminationDetection") { scope in
            Extends(.naturals)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let active = scope.sharedVar(in: Functions(from: Node, to: SetExpr<Bool>.literal(false, true)))
            let terminated = ForAll(in: Node) { node in !active[node] }
            let terminationDetected = scope.sharedVar(in: SetExpr<Bool>.literal(false, terminated))

            let TypeOK = Invariant()
            let TDCorrect = Invariant()
            let Quiescence = Temporal()
            let Liveness = Temporal()

            Do(Step.Terminate, over: Node) { node in
                When(active[node])
                Assign(active[node], to: false)
                With(SetExpr<Bool>.literal(terminationDetected, terminated)) { detected in
                    Assign(terminationDetected, to: detected)
                }
            }
            Do(Step.Wakeup, over: Node) { node in
                When(active[node])
                With(Node) { destination in
                    Assign(active[destination], to: true)
                }
            }
            let detectTermination = Do(Step.DetectTermination) {
                When(terminated)
                Assign(terminationDetected, to: true)
            }
            detectTermination
            WeakFairness(detectTermination)

            TypeOK {
                Functions(from: Node, to: SetExpr<Bool>.literal(false, true)).contains(active)
                    && SetExpr<Bool>.literal(false, true).contains(terminationDetected)
            }
            TDCorrect { !terminationDetected || terminated }
            Quiescence(.alwaysStep(on: terminated) { before, after in !before || after })
            Liveness(.leadsTo(terminated, terminationDetected))

            let SyncTerminationDetection = Validation {
                Bind(N, to: 7)
            }
            SyncTerminationDetection

            let APSyncTerminationDetection = Validation {
                Bind(N, to: 7)
            }.checking(only: [TypeOK, TDCorrect])
            APSyncTerminationDetection
        }
    }
}
