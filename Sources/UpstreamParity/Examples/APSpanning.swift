// Processes broadcast messages along graph edges to build a spanning tree in the Apalache
// variant.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/spanning/APspanning.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct APSpanningModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case p1 = "p1_OF_PROC", p2 = "p2_OF_PROC", p3 = "p3_OF_PROC", noParent = "noprnt_OF_PROC"
        package static var defaultValue: Self { .noParent }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("APspanning") { scope in
            Extends(.integers)
            let Proc = scope.parameter(as: Set<Node>.self, in: Subsets(of: Set<Node>([Node.p1, Node.p2, Node.p3])))
            let NoPrnt = scope.parameter(as: Node.self, in: Set<Node>([Node.noParent]))
            let root = scope.parameter(as: Node.self, in: Proc)
            let pairs = Proc.flatMapping { (i: WithValue<Node>) in
                Proc.mapping { (j: WithValue<Node>) in Pair<Node, Node>.literal(i, j) }
            }
            let nbrs = scope.parameter(as: Set<Pair<Node, Node>>.self, in: Subsets(of: pairs))
            Assume(!Proc.contains(NoPrnt) && nbrs.isSubset(of: pairs))
            let prnt: SharedVariable<[Node: Node]> = scope.sharedVar(initial:
                Dictionary<Node, Node>.mapping(over: Proc) { _ in NoPrnt.expr })
            let rpt = scope.sharedVar(initial: Dictionary<Node, Bool>.mapping(over: Proc) { _ in false })
            let msg = scope.sharedVar(initial: Set<Pair<Node, Node>>())

            Do(Step.next) {
                With(Proc, Proc) { (i: WithValue<Node>, j: WithValue<Node>) in
                    If(i != root && prnt[i] == NoPrnt && msg.contains(Pair<Node, Node>.literal(j, i))) {
                        prnt[i].set(j.expr)
                    } else: {
                        Either {
                            When(i == root || prnt[i] != NoPrnt) {
                                With(Proc) { k in
                                    let link = Pair<Node, Node>.literal(i, k)
                                    When(nbrs.contains(link) && !msg.contains(link))
                                    msg.insert(link)
                                }
                            }
                            When(prnt[i] != NoPrnt && !rpt[i]) { rpt[i].set(true) }
                            When(true) { Skip() }
                        }
                    }
                }
            }
            Invariant("TypeOK") {
                Proc.allSatisfy { i in
                    prnt[i] == NoPrnt || nbrs.contains(Pair<Node, Node>.literal(i, prnt[i]))
                }
                Functions(from: Proc, to: Bool.all).contains(rpt)
                msg.isSubset(of: pairs)
            }
            Validation("APspanning") {
                Bind(Proc, to: Set<Node>([Node.p1, Node.p2, Node.p3]))
                Bind(NoPrnt, to: Node.noParent)
                Bind(root, to: Node.p1)
                Bind(nbrs, to: Set<Pair<Node, Node>>([
                    Pair(first: Node.p1, second: Node.p2), Pair(first: Node.p2, second: Node.p1),
                    Pair(first: Node.p2, second: Node.p3), Pair(first: Node.p3, second: Node.p2)
                ]))
            }.behavior(.initialAndNext)
        }
    }
}
