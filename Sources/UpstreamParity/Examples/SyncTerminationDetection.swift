import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd840/SyncTerminationDetection.tla, SyncTerminationDetection.cfg.
@TLAModel
package struct SyncTerminationDetectionModel: Sendable {
    private enum Step: String, CaseIterable {
        case terminate = "Terminate"
        case wakeUp = "Wakeup"
        case detectTermination = "DetectTermination"
    }

    package static var spec: TLASpec {
        #spec("SyncTerminationDetection") { scope in
            Extends(.naturals)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = 0..<N
            let active = scope.sharedVar(initiallyIn: Functions(from: Node, to: Bool.all))
            let terminated = Node.allSatisfy { node in !active[node] }
            let terminationDetected = scope.sharedVar(initiallyIn: SetExpr<Bool>.literal(false, terminated))

            let Quiescence = Temporal()
            let Liveness = Temporal()

            Do(Step.terminate, over: Node) { node in
                When(active[node])
                active[node].set(false)
                With(SetExpr<Bool>.literal(terminationDetected, terminated)) { detected in
                    terminationDetected.set(detected)
                }
            }
            Do(Step.wakeUp, over: Node, Node) { node, destination in
                When(active[node])
                active[destination].set(true)
            }
            let detectTermination = Do(Step.detectTermination, when: terminated) {
                terminationDetected.set(true)
            }
            detectTermination
            WeakFairness(detectTermination)

            let typeOK = Invariant("TypeOK") {
                Functions(from: Node, to: Bool.all).contains(active)
                    && Bool.all.contains(terminationDetected)
            }
            typeOK
            let TDCorrect = Invariant { !terminationDetected || terminated }
            TDCorrect
            Quiescence(.alwaysStep(on: terminated) { before, after in !before || after })
            Liveness(.leadsTo(terminated, terminationDetected))

            let SyncTerminationDetection = Validation {
                Bind(N, to: 7)
            }
            SyncTerminationDetection

            let APSyncTerminationDetection = Validation {
                Bind(N, to: 7)
            }.checking(only: [typeOK, TDCorrect])
            APSyncTerminationDetection
        }
    }
}
