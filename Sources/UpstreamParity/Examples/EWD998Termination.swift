import SwiftTLA
import SwiftTLAMacros

/// Dijkstra's asynchronous ring-termination detector from EWD 998.
///
/// The finite node domain and its two shared functions are formal values.
/// Parameterized actions replace the old raw existential action bodies, so the
/// same authoring surface drives the parser, builder, and generated machine.
@TLAModel
public struct EWD998TerminationModel: Sendable {
    public enum Node: Int, CaseIterable, FiniteDomainKey {
        case zero = 0
        case one = 1
        case two = 2
        case three = 3

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.ewd998.node")

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("AsyncTerminationDetection") {
            Extends("Naturals")
            let active = SharedVar(in: SetExpr<Function<Node, Bool>>.literal(
                Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, false), (.three, false)),
                Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, false), (.three, true)),
                Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, true), (.three, false)),
                Function<Node, Bool>.literal((.zero, false), (.one, false), (.two, true), (.three, true)),
                Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, false), (.three, false)),
                Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, false), (.three, true)),
                Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, true), (.three, false)),
                Function<Node, Bool>.literal((.zero, false), (.one, true), (.two, true), (.three, true)),
                Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, false), (.three, false)),
                Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, false), (.three, true)),
                Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, true), (.three, false)),
                Function<Node, Bool>.literal((.zero, true), (.one, false), (.two, true), (.three, true)),
                Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, false), (.three, false)),
                Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, false), (.three, true)),
                Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, true), (.three, false)),
                Function<Node, Bool>.literal((.zero, true), (.one, true), (.two, true), (.three, true))
            ))
            let pending = SharedVar(initial: Function<Node, Int>.literal(
                (.zero, 0), (.one, 0), (.two, 0), (.three, 0)
            ))
            let terminationDetected = SharedVar(initial: false)

            Constraint(
                pending[.zero] <= 3 && pending[.one] <= 3
                    && pending[.two] <= 3 && pending[.three] <= 3
            )

            Invariant("TypeOK") {
                pending[.zero] >= 0 && pending[.one] >= 0
                    && pending[.two] >= 0 && pending[.three] >= 0
            }

            Invariant("Safe") {
                !terminationDetected || (
                    active[.zero] == false && active[.one] == false
                        && active[.two] == false && active[.three] == false
                        && pending[.zero] == 0 && pending[.one] == 0
                        && pending[.two] == 0 && pending[.three] == 0
                )
            }

            Action("Terminate", parameters: [
                ActionParameter("node", values: Node.finiteValues)
            ]) {
                let node = Expr<Node>(.variable("node"))
                active[node] == true
                    && active.becomes(active.updating(node, to: false))
                    && pending.stays
                    && (((active[.zero] == false && active[.one] == false
                        && active[.two] == false && active[.three] == false
                        && pending[.zero] == 0 && pending[.one] == 0
                        && pending[.two] == 0 && pending[.three] == 0)
                        && terminationDetected.becomes(true))
                        || ((active[.zero].expr.notEqual(false) || active[.one].expr.notEqual(false)
                            || active[.two].expr.notEqual(false) || active[.three].expr.notEqual(false)
                            || pending[.zero].expr.notEqual(0) || pending[.one].expr.notEqual(0)
                            || pending[.two].expr.notEqual(0) || pending[.three].expr.notEqual(0))
                            && terminationDetected.stays))
            }

            Action("RcvMsg", parameters: [
                ActionParameter("node", values: Node.finiteValues)
            ]) {
                let node = Expr<Node>(.variable("node"))
                pending[node] > 0
                    && active.becomes(active.updating(node, to: true))
                    && pending.becomes(pending.updating(node) { current in current - 1 })
                    && terminationDetected.stays
            }

            Action("SendMsg", parameters: [
                ActionParameter("sender", values: Node.finiteValues),
                ActionParameter("receiver", values: Node.finiteValues)
            ]) {
                let sender = Expr<Node>(.variable("sender"))
                let receiver = Expr<Node>(.variable("receiver"))
                active[sender] == true
                    && pending.becomes(pending.updating(receiver) { current in current + 1 })
                    && active.stays
                    && terminationDetected.stays
            }

            Action("DetectTermination") {
                active[.zero] == false && active[.one] == false
                    && active[.two] == false && active[.three] == false
                    && pending[.zero] == 0 && pending[.one] == 0
                    && pending[.two] == 0 && pending[.three] == 0
                    && terminationDetected.becomes(true)
                    && active.stays && pending.stays
            }
        }
    }
}

extension Example {
    public static let ewd998 = Entry(
        id: "ewd998/AsyncTerminationDetection",
        upstreamSpec: "ewd998",
        upstreamModule: "specifications/ewd998/AsyncTerminationDetection.tla",
        upstreamCfg: "specifications/ewd998/AsyncTerminationDetection.cfg",
        expectedDistinct: 4097,
        spec: EWD998TerminationModel.spec,
        notes: "N=4. Typed active/pending functions and parameterized asynchronous actions. Constraint pending<=3. Safe."
    )
}
