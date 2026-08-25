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

    package static var spec: TLASpec {
        #spec("EWD840") { scope in
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
            let color = scope.sharedVar("color", in: SetExpr<Function<Node, Color>>.literal(
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .white), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .white), (Node.two, .black)),
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .black), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .white), (Node.one, .black), (Node.two, .black)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .white), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .white), (Node.two, .black)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .black), (Node.two, .white)),
                Function<Node, Color>.literal((Node.zero, .black), (Node.one, .black), (Node.two, .black))
            ))
            let tpos = scope.sharedVar("tpos", in: 0...2)
            let tcolor = scope.sharedVar("tcolor", initial: Color.black)

            SwiftTLA.Action("InitiateProbe") {
                tpos == 0 && (tcolor == Color.black || color[.zero] == Color.black)
                    && tpos.becomes(2) && tcolor.becomes(.white)
                    && color.becomes(color.updating(.zero, to: .white)) && active.stays
            }

            SwiftTLA.Action("PassToken_1") {
                tpos == 1 && (active[.one] == false || color[.one] == Color.black || tcolor == Color.black)
                    && tpos.becomes(0)
                    && ((color[.one] == Color.black && tcolor.becomes(.black))
                        || (color[.one] != Color.black && tcolor.stays))
                    && color.becomes(color.updating(.one, to: .white)) && active.stays
            }
            SwiftTLA.Action("PassToken_2") {
                tpos == 2 && (active[.two] == false || color[.two] == Color.black || tcolor == Color.black)
                    && tpos.becomes(1)
                    && ((color[.two] == Color.black && tcolor.becomes(.black))
                        || (color[.two] != Color.black && tcolor.stays))
                    && color.becomes(color.updating(.two, to: .white)) && active.stays
            }

            SwiftTLA.Action("SendMsg_0_to_1") {
                active[.zero] == true && active.becomes(active.updating(.one, to: true))
                    && color.becomes(color.updating(.zero, to: .black)) && tpos.stays && tcolor.stays
            }
            SwiftTLA.Action("SendMsg_0_to_2") {
                active[.zero] == true && active.becomes(active.updating(.two, to: true))
                    && color.becomes(color.updating(.zero, to: .black)) && tpos.stays && tcolor.stays
            }
            SwiftTLA.Action("SendMsg_1_to_0") {
                active[.one] == true && active.becomes(active.updating(.zero, to: true))
                    && color.stays && tpos.stays && tcolor.stays
            }
            SwiftTLA.Action("SendMsg_1_to_2") {
                active[.one] == true && active.becomes(active.updating(.two, to: true))
                    && color.becomes(color.updating(.one, to: .black)) && tpos.stays && tcolor.stays
            }
            SwiftTLA.Action("SendMsg_2_to_0") {
                active[.two] == true && active.becomes(active.updating(.zero, to: true))
                    && color.stays && tpos.stays && tcolor.stays
            }
            SwiftTLA.Action("SendMsg_2_to_1") {
                active[.two] == true && active.becomes(active.updating(.one, to: true))
                    && color.stays && tpos.stays && tcolor.stays
            }

            Invariant("TypeOK") {
                tpos >= 0 && tpos < 3 && (tcolor == Color.white || tcolor == Color.black)
            }
        }
    }
}

extension Example {
    package static let ewd840 = Entry(
        id: "ewd840/EWD840",
        upstreamSpec: "ewd840",
        upstreamModule: "specifications/ewd840/EWD840.tla",
        upstreamCfg: "specifications/ewd840/EWD840.cfg",
        expectedDistinct: 258,
        spec: EWD840Model.spec,
        notes: "Dijkstra termination detection. N=3, typed active/color functions. TLC = 258."
    )
}
