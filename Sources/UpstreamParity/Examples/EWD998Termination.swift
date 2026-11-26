// Ring processes send and receive messages while a detector checks whether distributed work has
// finished.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/ewd998/AsyncTerminationDetection.tla

import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd998/AsyncTerminationDetection.tla and its N = 4 configuration.
@TLAModel
package struct EWD998TerminationModel: Sendable {
    private enum Step: String, CaseIterable {
        case terminate = "Terminate"
        case sendMessage = "SendMsg"
        case receiveMessage = "RcvMsg"
        case detectTermination = "DetectTermination"
    }

    package static var spec: TLASpec {
        #spec("AsyncTerminationDetection") { scope in
            Extends(.naturals)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                initiallyIn: Functions(from: Node, to: Bool.all))
            let pending = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: Node) { _ in 0 })
            let terminated = Node.allSatisfy { node in !active[node] && pending[node] == 0 }
            let terminationDetected = scope.sharedVar(initiallyIn: SetExpr<Bool>.literal(false, terminated))

            let Quiescence = Temporal()
            let Live = Temporal()

            Do(Step.terminate, over: Node) { node in
                When(active[node])
                active[node].set(false)
                With(SetExpr<Bool>.literal(terminationDetected, terminated)) { detected in
                    terminationDetected.set(detected)
                }
            }
            Do(Step.sendMessage, over: Node, Node) { sender, receiver in
                When(active[sender])
                pending[receiver] += 1
            }
            Do(Step.receiveMessage, over: Node) { node in
                When(pending[node] > 0)
                active[node].set(true)
                pending[node].set(pending[node] - 1)
            }
            let detectTermination = Do(Step.detectTermination, when: terminated) {
                terminationDetected.set(true)
            }
            detectTermination
            WeakFairness(detectTermination)

            Invariant("TypeOK") {
                Functions(from: Node, to: Bool.all).contains(active)
                    && Node.allSatisfy { node in pending[node] >= 0 }
                    && Bool.all.contains(terminationDetected)
            }
            Invariant("Safe") { !terminationDetected || terminated }
            Quiescence(.alwaysStep(on: terminated) { before, after in !before || after })
            Live(.leadsTo(terminated, terminationDetected))
            Constraint(Node.allSatisfy { node in pending[node] <= 3 })

            Validation("AsyncTerminationDetection") { Bind(N, to: 4) }
        }
    }
}
