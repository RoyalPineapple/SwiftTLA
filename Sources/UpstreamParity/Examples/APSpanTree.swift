// Nodes update their parent and distance toward a root in the Apalache version of the spanning-
// tree exercise.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpanningTree/APSpanTree.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct APSpanTreeModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1 = "n1_OF_NODE", n2 = "n2_OF_NODE", n3 = "n3_OF_NODE"
        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, CaseIterable { case relax = "Next" }

    package static var spec: TLASpec {
        #spec("APSpanTree") { scope in
            Extends(.integers, .finiteSets)
            let Nodes = scope.parameter(as: Set<Node>.self, in: Subsets(of: Set<Node>([Node.n1, Node.n2, Node.n3])))
            let Root = scope.parameter(as: Node.self, in: Nodes)
            let MaxCardinality = scope.parameter(as: Int.self, in: 3...3)
            Assume(Nodes.contains(Root) && MaxCardinality >= 0 && MaxCardinality >= Nodes.count)
            let Edges = scope.parameter(as: Set<Set<Node>>.self, in: Set<Set<Set<Node>>>([Set<Set<Node>>([[Node.n1, Node.n2], [Node.n2, Node.n3]])]))
            Assume(Edges.allSatisfy { edge in edge.isSubset(of: Nodes) && edge.count == 2 })
            let mom = scope.sharedVar(initial: Dictionary<Node, Node>.mapping(over: Nodes) { n in n.expr })
            let dist = scope.sharedVar(initial: Dictionary<Node, Int>.mapping(over: Nodes) { n in
                If(n == Root, then: 0, else: MaxCardinality)
            })

            Do(Step.relax) {
                With(Nodes, Nodes) { n, m in
                    When(Edges.contains(Set<Node>().inserting(n).inserting(m)) && dist[m] < 1 + dist[n])
                    With(IntRange(dist[m] + 1, through: dist[n] - 1)) { distance in
                        dist[n].set(distance)
                        mom[n].set(m)
                    }
                }
            }
            WeakFairnessNext()
            Invariant("TypeOK") {
                Functions(from: Nodes, to: Nodes).contains(mom)
                dist.keys == Nodes && Nodes.allSatisfy { n in dist[n] >= 0 }
            }
            Validation("Upstream") {
                Bind(Nodes, to: Set<Node>([Node.n1, Node.n2, Node.n3]))
                Bind(Root, to: Node.n1)
                Bind(MaxCardinality, to: 3)
                Bind(Edges, to: Set<Set<Node>>([[Node.n1, Node.n2], [Node.n2, Node.n3]]))
            }.checkingDeadlock(false)
        }
    }
}
