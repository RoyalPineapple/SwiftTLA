// A work list discovers all nodes reachable from the starting node.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/MisraReachability/Reachable.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ReachableModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4
        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case processFrontierOrFinish = "a"
        case terminating = "Terminating"
    }

    package static var spec: TLASpec {
        #spec("MCReachable") { scope in
            let population = Set<Node>([.n1, .n2, .n3, .n4])
            let nodes = scope.parameter(as: Set<Node>.self, in: Subsets(of: population))
            let start = scope.parameter(as: Node.self, in: population)
            let root = Set<Node>().inserting(start)
            let pairs = Subsets(of: nodes).filter { neighbors in neighbors.count == 2 }
            let successors = Select(from: Functions(from: nodes, to: pairs)) { _ in true }

            FormalDefinition("FollowsEdges", taking: [Node].self, Dictionary<Node, Set<Node>>.self) { path, graph -> Expr<Bool> in
                IntRange(1, through: path.count - 1).allSatisfy { i in
                    graph[path[i]].contains(path[i + 1])
                }
            }
            let paths = Sequences(of: nodes, lengths: IntRange(1, through: nodes.count))
            FormalDefinition("ReachableFrom", taking: Set<Node>.self, Dictionary<Node, Set<Node>>.self) { starts, graph -> Expr<Set<Node>> in
                nodes.filter { end in
                    paths.contains { path in
                        starts.contains(path[1]) && path[path.count] == end
                            && FormalCall(as: Bool.self, "FollowsEdges", path, graph)
                    }
                }
            }

            let marked = scope.sharedVar(initial: Set<Node>())
            let vroot = scope.sharedVar(initial: root)
            let pc = scope.sharedVar(initial: "a")

            let processFrontierOrFinish = Do(Step.processFrontierOrFinish) {
                When(pc == "a")
                If(vroot.isEmpty) {
                    pc.set("Done")
                } else: {
                    With(vroot) { node in
                        If(marked.contains(node)) {
                            vroot.remove(node)
                        } else: {
                            marked.insert(node)
                            vroot.formUnion(successors[node])
                        }
                    }
                }
            }
            let terminating = Do(Step.terminating) {
                When(pc == "Done")
                Skip()
            }
            WeakFairness(anyOf: [processFrontierOrFinish, terminating])

            let wellTyped = marked.isSubset(of: nodes) && vroot.isSubset(of: nodes)
                && Set<String>(["a", "Done"]).contains(pc) && (pc != "Done" || vroot.isEmpty)
            let discovered = marked.union(vroot)
            let reachable = FormalCall(as: Set<Node>.self, "ReachableFrom", root, successors)
            let remaining = FormalCall(as: Set<Node>.self, "ReachableFrom", vroot, successors)
            Invariant("TypeOK") { wellTyped }
            Invariant("Inv1") { wellTyped && marked.allSatisfy { node in successors[node].isSubset(of: discovered) } }
            Invariant("Inv2") { marked.union(remaining) == FormalCall(as: Set<Node>.self, "ReachableFrom", discovered, successors) }
            Invariant("Inv3") { reachable == marked.union(remaining) }
            Invariant("PartialCorrectness") { pc != "Done" || marked == reachable }
            Eventually("Termination", pc == "Done")
            Validation("Upstream") {
                Bind(nodes, to: population)
                Bind(start, to: Node.n1)
            }
        }
    }
}

extension Example {
    /// The static graph selection matches the published configuration shape.
    /// The graph comparator evaluates exact parity across TLC's `CHOOSE`
    /// ordering and SwiftTLA's compiled transitions.
    package static let reachable = FiniteModelFixture(
        expectedDistinct: 8,
        maximumStateLimit: 50_000,
        spec: ReachableModel.spec,
    )
}
