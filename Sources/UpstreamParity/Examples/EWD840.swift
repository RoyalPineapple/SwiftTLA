import SwiftTLA
import SwiftTLAMacros

/// Dijkstra's termination detector from EWD 840.
@TLAModel
package struct EWD840Model: Sendable {
    package enum Color: String, TLAValueType {
        case white
        case black

        package static var defaultValue: Self { .white }
    }

    private enum Step: String, CaseIterable {
        case initiateProbe = "InitiateProbe"
        case passToken = "PassToken"
        case sendMessage = "SendMsg"
        case deactivate = "Deactivate"
    }

    package static var spec: TLASpec {
        #spec("EWD840") { scope in
            Extends(.naturals)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let Node = 0..<N
            let colors = SetExpr<Color>.literal(.white, .black)
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(
                initiallyIn: Functions(from: Node, to: SetExpr<Bool>.literal(false, true)))
            let color: SharedVariable<[Int: Color]> = scope.sharedVar(initiallyIn: Functions(from: Node, to: colors))
            let tpos = scope.sharedVar(initiallyIn: Node)
            let tcolor = scope.sharedVar(initial: Color.black)

            let initiate = Do(Step.initiateProbe, when: tpos == 0
                && (tcolor == Color.black || color[0] == Color.black)) {
                tpos.set(N - 1)
                tcolor.set(Color.white)
                color[0].set(Color.white)
            }
            initiate

            let pass = Do(Step.passToken, over: Node) { i in
                When(i != 0 && tpos == i
                    && (!active[i] || color[i] == Color.black || tcolor == Color.black))
                tpos.set(i - 1)
                tcolor.set(If(color[i] == Color.black, then: Color.black, else: tcolor))
                color[i].set(Color.white)
            }
            pass
            WeakFairness(anyOf: [initiate, pass])

            Do(Step.sendMessage, over: Node) { i in
                When(active[i])
                With(Node) { j in
                    When(j != i)
                    active[j].set(true)
                    If(j > i) {
                        color[i].set(Color.black)
                    }
                }
            }

            Do(Step.deactivate, over: Node) { i in
                When(active[i])
                active[i].set(false)
            }

            let Liveness = Temporal()
            let terminated = Node.allSatisfy { i in !active[i] }
            let terminationDetected = tpos == 0 && tcolor == Color.white
                && color[0] == Color.white && !active[0]
            let typeOK = Invariant("TypeOK") {
                Functions(from: Node, to: SetExpr<Bool>.literal(false, true)).contains(active)
                    && Functions(from: Node, to: colors).contains(color)
                    && Node.contains(tpos) && colors.contains(tcolor)
            }
            typeOK
            let terminationDetection = Invariant("TerminationDetection") { !terminationDetected || terminated }
            terminationDetection
            let inductiveInvariant = Node.allSatisfy { i in tpos >= i || !active[i] }
                || IntRange(0, through: tpos).contains { i in color[i] == Color.black }
                || tcolor == Color.black
            let inv = Invariant("Inv") { inductiveInvariant }
            inv
            // The upstream JSON trace/exit effect belongs to validation, not the state predicate.
            let jsonInv = Invariant("JsonInv") { inductiveInvariant }
            jsonInv
            Liveness(.leadsTo(terminated, terminationDetected))

            let TD = Instance(of: SyncTerminationDetectionModel.self) {
                Bind(\.N, to: N)
            }
            TD
            let TDSpec = Refinement(instance: TD) {
                Map(\.active, from: active)
                Map(\.terminationDetected, from: terminationDetected)
            }
            TDSpec

            let EWD840 = Validation { Bind(N, to: 3) }
                .checking(only: [typeOK, terminationDetection, inv, Liveness, TDSpec])
                .checkingDeadlock(false)
            EWD840
            let APEWD840 = Validation { Bind(N, to: 3) }
                .checking(only: [typeOK, terminationDetection])
                .checkingDeadlock(false)
            APEWD840
            let EWD840_json = Validation { Bind(N, to: 4) }
                .checking(only: [jsonInv])
                .checkingDeadlock(false)
            EWD840_json
        }
    }
}
