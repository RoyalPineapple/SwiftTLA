// Nodes can send messages to any node. Termination requires every node to be inactive with no messages pending.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/ewd998/AsyncTerminationDetection.tla

import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd998/AsyncTerminationDetection.tla and its N = 4 configuration.
@TLAModel
package struct EWD998TerminationModel: Sendable {
    private enum Step: String, CaseIterable {
        case deactivateNode = "Terminate"
        case sendMessage = "SendMsg"
        case receiveMessage = "RcvMsg"
        case detectTermination = "DetectTermination"
    }

    package static var spec: TLASpec {
        #spec("AsyncTerminationDetection") { scope in
            Extends(.naturals)
            let nodeCount = scope.parameter(tlaName: "N", as: Int.self, in: Int.all)
            Assume(nodeCount > 0)
            let nodes = IntRange(0, through: nodeCount - 1)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                initiallyIn: Functions(from: nodes, to: Bool.all))
            let pendingMessages = scope.sharedVar(tlaName: "pending", initial: Dictionary<Int, Int>.mapping(over: nodes) { _ in 0 })
            let terminated = nodes.allSatisfy { node in !active[node] && pendingMessages[node] == 0 }
            let terminationDetected = scope.sharedVar(initiallyIn: SetExpr<Bool>.literal(false, terminated))

            let Quiescence = Temporal()
            let Live = Temporal()

            Do(Step.deactivateNode, over: nodes) { node in
                When(active[node])
                active[node].set(false)
                With(SetExpr<Bool>.literal(terminationDetected, terminated)) { detected in
                    terminationDetected.set(detected)
                }
            }
            Do(Step.sendMessage, over: nodes, nodes) { sender, receiver in
                When(active[sender])
                pendingMessages[receiver] += 1
            }
            Do(Step.receiveMessage, over: nodes) { node in
                When(pendingMessages[node] > 0)
                active[node].set(true)
                pendingMessages[node].set(pendingMessages[node] - 1)
            }
            let detectTermination = Do(Step.detectTermination, when: terminated) {
                terminationDetected.set(true)
            }
            WeakFairness(detectTermination)

            Invariant("TypeOK") {
                Functions(from: nodes, to: Bool.all).contains(active)
                    && nodes.allSatisfy { node in pendingMessages[node] >= 0 }
                    && Bool.all.contains(terminationDetected)
            }
            Invariant("Safe") { !terminationDetected || terminated }
            Quiescence(.alwaysStep(on: terminated) { before, after in !before || after })
            Live(.leadsTo(terminated, terminationDetected))
            Constraint(nodes.allSatisfy { node in pendingMessages[node] <= 3 })

            Validation("AsyncTerminationDetection") { Bind(nodeCount, to: 4) }
        }
    }
}
