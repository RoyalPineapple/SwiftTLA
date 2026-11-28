// Four identities about reachability, checked over all graphs or over five sampled graphs.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/MisraReachability/MCReachabilityTest.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ReachabilityAssumptions: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4
        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package static var spec: TLASpec {
        #spec("MCReachabilityTest") { scope in
            Extends(.tlc)
            let domain = Set<Node>([.n1, .n2, .n3, .n4])
            let nodes = scope.parameter(tlaName: "Nodes", as: Set<Node>.self, in: Subsets(of: domain))
            let samples = scope.parameter(tlaName: "RandomSuccCount", as: Int.self, in: Int.all)
            let subsets = Subsets(of: nodes)
            let allGraphs = Functions(from: nodes, to: subsets)
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

            FormalDefinition("CheckGraph", taking: Dictionary<Node, Set<Node>>.self) { graph -> Expr<Bool> in
                subsets.allSatisfy { s in
                    let reachable = FormalCall(as: Set<Node>.self, "ReachableFrom", s, graph)
                    return s.isSubset(of: reachable)
                        && subsets.allSatisfy { t in
                            !s.allSatisfy { n in graph[n].isSubset(of: s.union(t)) }
                                || s.union(FormalCall(as: Set<Node>.self, "ReachableFrom", t, graph))
                                    == FormalCall(as: Set<Node>.self, "ReachableFrom", s.union(t), graph)
                        }
                        && s.allSatisfy { n in reachable.contains(n) && reachable == FormalCall(as: Set<Node>.self, "ReachableFrom", s.union(graph[n]), graph) }
                } && FormalCall(as: Set<Node>.self, "ReachableFrom", Set<Node>(), graph).isEmpty
            }
            let sampledGraphs = IntRange(1, through: samples).mapping { _ in
                Dictionary<Node, Set<Node>>.mapping(over: nodes) { _ in RandomElement(from: subsets) }
            }
            Assume(If(samples == 0, then: allGraphs.allSatisfy { graph in
                FormalCall(as: Bool.self, "CheckGraph", graph)
            }, else: sampledGraphs.allSatisfy { graph in
                FormalCall(as: Bool.self, "CheckGraph", graph)
            }))
            Validation("AllGraphs") {
                Bind(nodes, to: Set<Node>([.n1, .n2, .n3]))
                Bind(samples, to: 0)
            }.checkingDeadlock(false)
            Validation("RandomGraphs") {
                Bind(nodes, to: Set<Node>([.n1, .n2, .n3, .n4]))
                Bind(samples, to: 5)
            }.checkingDeadlock(false)
        }
    }
}
