import SwiftTLA
import SwiftTLAMacros

/// Dijkstra's three-node termination detector from EWD 840.
@TLAModel
package struct EWD840Model: Sendable {
    package enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case zero = 0
        case one = 1
        case two = 2

        package static var defaultValue: Self { .zero }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .int(rawValue) }
    }

    package enum Color: String, TLAValueType {
        case white
        case black

        package static var defaultValue: Self { .white }
    }

    private enum Step: String, CaseIterable {
        case InitiateProbe, PassToken_1, PassToken_2
        case SendMsg_0_to_1, SendMsg_0_to_2, SendMsg_1_to_0
        case SendMsg_1_to_2, SendMsg_2_to_0, SendMsg_2_to_1
        case Deactivate_0, Deactivate_1, Deactivate_2
    }

    package static var spec: TLASpec {
        #spec("EWD840") { scope in
            Extends(.integers)
            let active = scope.sharedVar(in: SetExpr<Function<Node, Bool>>.literal(
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, false), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, false), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, true), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, false), (Node.one, true), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, false), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, false), (Node.two, true)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, true), (Node.two, false)),
                Function<Node, Bool>.literal((Node.zero, true), (Node.one, true), (Node.two, true))
            ))
            let color = scope.sharedVar(in: SetExpr<Function<Node, Color>>.literal(
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .white), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .white), (Node.two, .black)),
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .black), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .black), (Node.two, .black)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .white), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .white), (Node.two, .black)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .black), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .black), (Node.two, .black))
            ))
            let tpos = scope.sharedVar(in: 0...2)
            let tcolor = scope.sharedVar(initial: Color.black)

            Do(Step.InitiateProbe, when: tpos == 0
                && (tcolor == Color.black || color[.zero] == Color.black)) {
                Assign(tpos, to: 2)
                Assign(tcolor, to: Color.white)
                Assign(color, to: color.updating(.zero, to: .white))
            }

            Do(Step.PassToken_1, when: tpos == 1
                && (active[.one] == false || color[.one] == Color.black || tcolor == Color.black)) {
                Assign(tpos, to: 0)
                Assign(tcolor, to: If(color[.one] == Color.black, then: Color.black, else: tcolor))
                Assign(color, to: color.updating(.one, to: .white))
            }
            Do(Step.PassToken_2, when: tpos == 2
                && (active[.two] == false || color[.two] == Color.black || tcolor == Color.black)) {
                Assign(tpos, to: 1)
                Assign(tcolor, to: If(color[.two] == Color.black, then: Color.black, else: tcolor))
                Assign(color, to: color.updating(.two, to: .white))
            }

            Do(Step.SendMsg_0_to_1, when: active[.zero]) {
                Assign(active, to: active.updating(.one, to: true))
                Assign(color, to: color.updating(.zero, to: .black))
            }
            Do(Step.SendMsg_0_to_2, when: active[.zero]) {
                Assign(active, to: active.updating(.two, to: true))
                Assign(color, to: color.updating(.zero, to: .black))
            }
            Do(Step.SendMsg_1_to_0, when: active[.one]) {
                Assign(active, to: active.updating(.zero, to: true))
            }
            Do(Step.SendMsg_1_to_2, when: active[.one]) {
                Assign(active, to: active.updating(.two, to: true))
                Assign(color, to: color.updating(.one, to: .black))
            }
            Do(Step.SendMsg_2_to_0, when: active[.two]) {
                Assign(active, to: active.updating(.zero, to: true))
            }
            Do(Step.SendMsg_2_to_1, when: active[.two]) {
                Assign(active, to: active.updating(.one, to: true))
            }

            Do(Step.Deactivate_0, when: active[.zero]) {
                Assign(active, to: active.updating(.zero, to: false))
            }
            Do(Step.Deactivate_1, when: active[.one]) {
                Assign(active, to: active.updating(.one, to: false))
            }
            Do(Step.Deactivate_2, when: active[.two]) {
                Assign(active, to: active.updating(.two, to: false))
            }

            let TypeOK = Invariant()
            TypeOK {
                tpos >= 0 && tpos < 3 && (tcolor == Color.white || tcolor == Color.black)
            }
        }
    }
}

extension Example {
    package static let ewd840 = FiniteModelFixture(
        expectedDistinct: 302,
        maximumStateLimit: 50_000,
        spec: EWD840Model.spec,
    )
}
