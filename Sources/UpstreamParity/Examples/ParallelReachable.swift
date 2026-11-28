// Workers share a frontier. Unpublished discoveries belong to the sequential frontier until transferred.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/MisraReachability/ParReach.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ParallelReachableModel: Sendable {
    package enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4
        package static var defaultValue: Self { .n1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum Worker: String, CaseIterable, FiniteTLAValueDomain {
        case p1, p2
        package static var defaultValue: Self { .p1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case claimFrontierNode = "a"
        case markOrRemoveNode = "b"
        case publishNextSuccessor = "c"
    }

    package static var spec: TLASpec {
        #spec("MCParReach") { scope in
            let population = Set<Node>([.n1, .n2, .n3, .n4])
            let nodes = scope.parameter(tlaName: "Nodes", as: Set<Node>.self, in: Subsets(of: population))
            let start = scope.parameter(tlaName: "Root", as: Node.self, in: population)
            let workers = scope.parameter(tlaName: "Procs", as: Set<Worker>.self, in: Subsets(of: Set<Worker>([.p1, .p2])))
            let pairs = Subsets(of: nodes).filter { neighbors in neighbors.count == 2 }
            let successors = Select(from: Functions(from: nodes, to: pairs)) { _ in true }
            let marked = scope.sharedVar(initial: Set<Node>())
            let vroot = scope.sharedVar(initial: Set<Node>().inserting(start))
            let u = scope.sharedVar(initial: Dictionary<Worker, Node>.mapping(over: workers) { _ in start })
            let toVroot = scope.sharedVar(initial: Dictionary<Worker, Set<Node>>.mapping(over: workers) { _ in Set<Node>() })
            Algorithm("ParReach") {
                Each(workers, fairness: .weak) { worker in
                    Do(Step.claimFrontierNode) {
                        If(vroot.isEmpty) {
                            Stop()
                        } else: {
                            With(vroot) { node in u[worker].set(node) }
                            Goto(Step.markOrRemoveNode)
                        }
                    }
                    Do(Step.markOrRemoveNode) {
                        If(marked.contains(u[worker])) {
                            vroot.remove(u[worker])
                            Goto(Step.claimFrontierNode)
                        } else: {
                            marked.insert(u[worker])
                            toVroot[worker].set(successors[u[worker]])
                            Goto(Step.publishNextSuccessor)
                        }
                    }
                    Do(Step.publishNextSuccessor) {
                        If(toVroot[worker].isEmpty) {
                            Goto(Step.claimFrontierNode)
                        } else: {
                            With(toVroot[worker]) { node in
                                vroot.insert(node)
                                toVroot[worker].set(toVroot[worker].removing(node))
                            }
                            Goto(Step.publishNextSuccessor)
                        }
                    }
                }
            }
            let done = workers.allSatisfy { q in Finished(q) }
            Invariant("Inv") {
                marked.isSubset(of: nodes) && vroot.isSubset(of: nodes)
                u.keys == workers && toVroot.keys == workers
                workers.allSatisfy { q in
                    nodes.contains(u[q]) && toVroot[q].isSubset(of: nodes)
                        && (q.isAt(anyOf: Step.claimFrontierNode, .markOrRemoveNode, .publishNextSuccessor) || Finished(q))
                        && (q.isAt(anyOf: Step.publishNextSuccessor) || toVroot[q].isEmpty)
                        && (!q.isAt(anyOf: Step.markOrRemoveNode) || vroot.union(marked).contains(u[q]))
                }
            }
            let sequential = Instance(of: ReachableModel.self) {
                Bind(\.nodes, projecting: nodes)
                Bind(\.start, projecting: start)
            }
            let frontier = vroot.union(workers.flatMapping { q in toVroot[q] })
            let control = If(done, then: "Done", else: "a")
            Refinement("Refines", instance: sequential) {
                Map(\.marked, projecting: marked)
                Map(\.vroot, projecting: frontier)
                Map(\.pc, projecting: control)
            }
            Validation("Upstream") {
                Bind(nodes, to: population)
                Bind(start, to: Node.n1)
                Bind(workers, to: Set<Worker>([.p1, .p2]))
            }
        }
    }
}

extension Example {
    package static let parallelReachable = FiniteModelFixture(
        expectedDistinct: 393,
        maximumStateLimit: 50_000,
        spec: ParallelReachableModel.spec,
    )
}
