import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/ewd998/AsyncTerminationDetection.tla and its N = 4 configuration.
@TLAModel
package struct EWD998TerminationModel: Sendable {
    private enum Step: String, CaseIterable {
        case Terminate, SendMsg, RcvMsg, DetectTermination
    }

    package static var spec: TLASpec {
        #spec("AsyncTerminationDetection") { scope in
            Extends(.naturals)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = IntRange(0, through: N - 1)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                in: Functions(from: Node, to: SetExpr<Bool>.literal(false, true)))
            let pending = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: Node) { _ in 0 })
            let terminated = ForAll(in: Node) { node in !active[node] && pending[node] == 0 }
            let terminationDetected = scope.sharedVar(in: SetExpr<Bool>.literal(false, terminated))

            let TypeOK = Invariant()
            let Safe = Invariant()
            let Quiescence = Temporal()
            let Live = Temporal()

            Do(Step.Terminate, over: Node) { node in
                When(active[node])
                Assign(active[node], to: false)
                With(SetExpr<Bool>.literal(terminationDetected, terminated)) { detected in
                    Assign(terminationDetected, to: detected)
                }
            }
            Do(Step.SendMsg, over: Node, Node) { sender, receiver in
                When(active[sender])
                Assign(pending[receiver], to: pending[receiver] + 1)
            }
            Do(Step.RcvMsg, over: Node) { node in
                When(pending[node] > 0)
                Assign(active[node], to: true)
                Assign(pending[node], to: pending[node] - 1)
            }
            let detectTermination = Do(Step.DetectTermination) {
                When(terminated)
                Assign(terminationDetected, to: true)
            }
            detectTermination
            WeakFairness(detectTermination)

            TypeOK {
                Functions(from: Node, to: SetExpr<Bool>.literal(false, true)).contains(active)
                    && ForAll(in: Node) { node in pending[node] >= 0 }
                    && SetExpr<Bool>.literal(false, true).contains(terminationDetected)
            }
            Safe { !terminationDetected || terminated }
            Quiescence(.alwaysStep(on: terminated) { before, after in !before || after })
            Live(.leadsTo(terminated, terminationDetected))
            Constraint(ForAll(in: Node) { node in pending[node] <= 3 })

            let AsyncTerminationDetection = Validation { Bind(N, to: 4) }
            AsyncTerminationDetection
        }
    }
}
