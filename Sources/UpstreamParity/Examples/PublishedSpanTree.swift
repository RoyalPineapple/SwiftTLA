// Nodes relax distances and choose a parent along a path toward the root.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpanningTree/SpanTree.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct PublishedSpanTreeModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4, n5
        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable { case relax = "Next" }

    package static var spec: TLASpec {
        #spec("SpanTree") { scope in
            Extends(.integers, .finiteSets)
            let Nodes = scope.parameter(as: Set<Node>.self, in: Subsets(of: Set<Node>([Node.n1, Node.n2, Node.n3, Node.n4, Node.n5])))
            let Root = scope.parameter(as: Node.self, in: Nodes)
            let MaxCardinality = scope.parameter(as: Int.self, in: 6...6)
            Assume(Nodes.contains(Root) && MaxCardinality >= 0 && MaxCardinality >= Nodes.count)
            let Edges = scope.parameter(as: Set<Set<Node>>.self, in: Set<Set<Set<Node>>>([Set<Set<Node>>([[Node.n1, Node.n2], [Node.n1, Node.n3], [Node.n2, Node.n3], [Node.n2, Node.n4], [Node.n3, Node.n4], [Node.n3, Node.n5], [Node.n4, Node.n5]])]))
            Assume(Edges.allSatisfy { edge in edge.isSubset(of: Nodes) && edge.count == 2 })
            let mom = scope.sharedVar(initial: Dictionary<Node, Node>.mapping(over: Nodes) { n in n.expr })
            let dist = scope.sharedVar(initial: Dictionary<Node, Int>.mapping(over: Nodes) { n in
                If(n == Root, then: 0, else: MaxCardinality)
            })

            let relax = Do(Step.relax) {
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

            let postCondition = Nodes.allSatisfy { n in
                let rootIsCorrect = n == Root && dist[n] == 0 && mom[n] == n
                let unreachable = dist[n] == MaxCardinality && mom[n] == n && Nodes.allSatisfy { m in
                    !Edges.contains(Set<Node>().inserting(n).inserting(m)) || dist[m] == MaxCardinality
                }
                let linked = dist[n] >= 1 && dist[n] < MaxCardinality
                    && Edges.contains(Set<Node>().inserting(n).inserting(mom[n])) && dist[n] == dist[mom[n]] + 1
                return rootIsCorrect || unreachable || linked
            }
            let Safety = Temporal()
            Safety(.always(relax.enabled || postCondition))
            let Liveness = Temporal()
            Liveness(.eventually(!relax.enabled))
            Validation("Upstream") {
                Bind(Nodes, to: Set<Node>([Node.n1, Node.n2, Node.n3, Node.n4, Node.n5]))
                Bind(Root, to: Node.n1)
                Bind(MaxCardinality, to: 6)
                Bind(Edges, to: Set<Set<Node>>([[Node.n1, Node.n2], [Node.n1, Node.n3], [Node.n2, Node.n3], [Node.n2, Node.n4], [Node.n3, Node.n4], [Node.n3, Node.n5], [Node.n4, Node.n5]]))
            }.checkingDeadlock(false)
        }
    }
}
