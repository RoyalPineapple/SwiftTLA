// Two workers mark a shared frontier and publish one successor at a time.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/MisraReachability/APParReach.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct APParallelReachabilityModel: Sendable {
    private enum Step: String, CaseIterable {
        case takeFrontierNode = "a", inspectNode = "b", publishSuccessor = "c"
    }

    package static var spec: TLASpec {
        #spec("APParReach") { model in
            Extends(.integers, .finiteSets)
            let nodeValues = Set<String>(["n1_OF_NODE", "n2_OF_NODE", "n3_OF_NODE"])
            let workerValues = Set<String>(["p1_OF_PROC", "p2_OF_PROC"])
            let nodes = model.parameter(tlaName: "Nodes", as: Set<String>.self, in: Subsets(of: nodeValues))
            let workers = model.parameter(tlaName: "Procs", as: Set<String>.self, in: Subsets(of: workerValues))
            let root = model.parameter(tlaName: "Root", as: String.self, in: nodeValues)
            let successors = Dictionary<String, Set<String>>.mapping(over: nodes) { node in nodes.removing(node) }
            Assume(nodes.contains(root) && !workers.isEmpty)
            let invariant = Invariant("Inv")
            Algorithm("ParallelReachability") { scope in
                let marked = scope.sharedVar(initial: Set<String>())
                let frontier = scope.sharedVar(tlaName: "vroot", initial: Set<String>().inserting(root))
                let current = scope.sharedVar(tlaName: "u", initial: Dictionary<String, String>.mapping(over: workers) { _ in root })
                let pending = scope.sharedVar(tlaName: "toVroot", initial: Dictionary<String, Set<String>>.mapping(over: workers) { _ in Set<String>() })
                Each(workers, fairness: .weak) { worker in
                    Do(Step.takeFrontierNode) {
                        If(frontier.isEmpty) { Stop() } else: {
                            With(frontier) { node in current[worker].set(node) }
                            Goto(Step.inspectNode)
                        }
                    }
                    Do(Step.inspectNode) {
                        If(marked.contains(current[worker])) {
                            frontier.remove(current[worker])
                            Goto(Step.takeFrontierNode)
                        } else: {
                            marked.insert(current[worker])
                            pending[worker].set(successors[current[worker]])
                            Goto(Step.publishSuccessor)
                        }
                    }
                    Do(Step.publishSuccessor) {
                        If(pending[worker].isEmpty) { Goto(Step.takeFrontierNode) } else: {
                            With(pending[worker]) { node in
                                frontier.insert(node)
                                pending[worker].remove(node)
                            }
                            Goto(Step.publishSuccessor)
                        }
                    }
                }
                invariant {
                    marked.isSubset(of: nodes) && frontier.isSubset(of: nodes)
                    Functions(from: workers, to: nodes).contains(current)
                    pending.keys == workers && workers.allSatisfy { w in pending[w].isSubset(of: nodes) }
                    workers.allSatisfy { w in
                        (w.isAt(anyOf: Step.takeFrontierNode, .inspectNode, .publishSuccessor) || Finished(w))
                            && (!(w.isAt(anyOf: Step.takeFrontierNode, .inspectNode) || Finished(w)) || pending[w].isEmpty)
                            && (!w.isAt(anyOf: Step.inspectNode) || frontier.union(marked).contains(current[w]))
                    }
                }
            }
            Validation("APParReach") {
                Bind(nodes, to: nodeValues)
                Bind(workers, to: workerValues)
                Bind(root, to: "n1_OF_NODE")
            }.behavior(.initialAndNext)
        }
    }
}
