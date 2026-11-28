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
            let nodes = scope.parameter(tlaName: "Nodes", as: Set<Node>.self, in: Subsets(of: Set<Node>([Node.n1, Node.n2, Node.n3, Node.n4, Node.n5])))
            let root = scope.parameter(tlaName: "Root", as: Node.self, in: nodes)
            let maxCardinality = scope.parameter(tlaName: "MaxCardinality", as: Int.self, in: 6...6)
            Assume(nodes.contains(root) && maxCardinality >= 0 && maxCardinality >= nodes.count)
            let edges = scope.parameter(tlaName: "Edges", as: Set<Set<Node>>.self, in: Set<Set<Set<Node>>>([Set<Set<Node>>([[Node.n1, Node.n2], [Node.n1, Node.n3], [Node.n2, Node.n3], [Node.n2, Node.n4], [Node.n3, Node.n4], [Node.n3, Node.n5], [Node.n4, Node.n5]])]))
            Assume(edges.allSatisfy { edge in edge.isSubset(of: nodes) && edge.count == 2 })
            let parent = scope.sharedVar(tlaName: "mom", initial: Dictionary<Node, Node>.mapping(over: nodes) { n in n.expr })
            let distanceFromRoot = scope.sharedVar(tlaName: "dist", initial: Dictionary<Node, Int>.mapping(over: nodes) { n in
                If(n == root, then: 0, else: maxCardinality)
            })

            let relax = Do(Step.relax) {
                With(nodes, nodes) { n, m in
                    When(edges.contains(Set<Node>().inserting(n).inserting(m)) && distanceFromRoot[m] < 1 + distanceFromRoot[n])
                    With(IntRange(distanceFromRoot[m] + 1, through: distanceFromRoot[n] - 1)) { distance in
                        distanceFromRoot[n].set(distance)
                        parent[n].set(m)
                    }
                }
            }
            WeakFairnessNext()
            Invariant("TypeOK") {
                Functions(from: nodes, to: nodes).contains(parent)
                distanceFromRoot.keys == nodes && nodes.allSatisfy { n in distanceFromRoot[n] >= 0 }
            }

            let postCondition = nodes.allSatisfy { n in
                let rootIsCorrect = n == root && distanceFromRoot[n] == 0 && parent[n] == n
                let unreachable = distanceFromRoot[n] == maxCardinality && parent[n] == n && nodes.allSatisfy { m in
                    !edges.contains(Set<Node>().inserting(n).inserting(m)) || distanceFromRoot[m] == maxCardinality
                }
                let linked = distanceFromRoot[n] >= 1 && distanceFromRoot[n] < maxCardinality
                    && edges.contains(Set<Node>().inserting(n).inserting(parent[n])) && distanceFromRoot[n] == distanceFromRoot[parent[n]] + 1
                return rootIsCorrect || unreachable || linked
            }
            let Safety = Temporal()
            Safety(.always(relax.enabled || postCondition))
            let Liveness = Temporal()
            Liveness(.eventually(!relax.enabled))
            Validation("Upstream") {
                Bind(nodes, to: Set<Node>([Node.n1, Node.n2, Node.n3, Node.n4, Node.n5]))
                Bind(root, to: Node.n1)
                Bind(maxCardinality, to: 6)
                Bind(edges, to: Set<Set<Node>>([[Node.n1, Node.n2], [Node.n1, Node.n3], [Node.n2, Node.n3], [Node.n2, Node.n4], [Node.n3, Node.n4], [Node.n3, Node.n5], [Node.n4, Node.n5]]))
            }.checkingDeadlock(false)
        }
    }
}
