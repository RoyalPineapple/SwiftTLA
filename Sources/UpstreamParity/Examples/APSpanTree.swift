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
            let nodes = scope.parameter(tlaName: "Nodes", as: Set<Node>.self, in: Subsets(of: Set<Node>([Node.n1, Node.n2, Node.n3])))
            let root = scope.parameter(tlaName: "Root", as: Node.self, in: nodes)
            let maxCardinality = scope.parameter(tlaName: "MaxCardinality", as: Int.self, in: 3...3)
            Assume(nodes.contains(root) && maxCardinality >= 0 && maxCardinality >= nodes.count)
            let edges = scope.parameter(tlaName: "Edges", as: Set<Set<Node>>.self, in: Set<Set<Set<Node>>>([Set<Set<Node>>([[Node.n1, Node.n2], [Node.n2, Node.n3]])]))
            Assume(edges.allSatisfy { edge in edge.isSubset(of: nodes) && edge.count == 2 })
            let parent = scope.sharedVar(tlaName: "mom", initial: Dictionary<Node, Node>.mapping(over: nodes) { n in n.expr })
            let distanceFromRoot = scope.sharedVar(tlaName: "dist", initial: Dictionary<Node, Int>.mapping(over: nodes) { n in
                If(n == root, then: 0, else: maxCardinality)
            })

            Do(Step.relax) {
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
            Validation("Upstream") {
                Bind(nodes, to: Set<Node>([Node.n1, Node.n2, Node.n3]))
                Bind(root, to: Node.n1)
                Bind(maxCardinality, to: 3)
                Bind(edges, to: Set<Set<Node>>([[Node.n1, Node.n2], [Node.n2, Node.n3]]))
            }.checkingDeadlock(false)
        }
    }
}
