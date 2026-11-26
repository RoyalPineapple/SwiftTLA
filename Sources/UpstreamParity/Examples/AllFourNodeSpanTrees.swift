// The model chooses a graph on four nodes, then updates parent pointers and distances toward the
// root.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpanningTree/SpanTreeTest.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct AllFourNodeSpanTreesModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4
        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable { case relax = "Next" }

    package static var spec: TLASpec {
        #spec("SpanTreeTest") { scope in
            Extends(.integers, .finiteSets)
            let Nodes = scope.parameter(as: Set<Node>.self, in: Subsets(of: Set<Node>([Node.n1, Node.n2, Node.n3, Node.n4])))
            let Root = scope.parameter(as: Node.self, in: Nodes)
            let MaxCardinality = scope.parameter(as: Int.self, in: 5...5)
            Assume(Nodes.contains(Root) && MaxCardinality >= 0 && MaxCardinality >= Nodes.count)
            let possibleEdges = Where(Subsets(of: Nodes)) { edge in edge.count == 2 }
            let Edges = scope.sharedVar(initiallyIn: Subsets(of: possibleEdges))
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
                Edges.allSatisfy { edge in edge.isSubset(of: Nodes) && edge.count == 2 }
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
            Liveness(.eventually(postCondition))
            Validation("Upstream") {
                Bind(Nodes, to: Set<Node>([Node.n1, Node.n2, Node.n3, Node.n4]))
                Bind(Root, to: Node.n1)
                Bind(MaxCardinality, to: 5)
            }.checkingDeadlock(false)
        }
    }
}
