import SwiftTLA
import SwiftTLAMacros

/// The two-worker PlusCal companion to Misra's reachable-node algorithm.
///
/// Each worker claims one frontier node, marks it, then moves its successor
/// nodes into the shared frontier one at a time. The separate `a`, `b`, and
/// `c` steps deliberately mirror the published PlusCal labels.
public struct ParallelReachableModel: Sendable {
    public enum Node: Int, FiniteDomainKey {
        case one = 1, two = 2, three = 3, four = 4

        public static var defaultValue: Self { .one }
        public static let formalDomain: [Self] = [.one, .two, .three, .four]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.parallel-reachable.node")
        public var tlaValue: TLAValue { .int(rawValue) }
    }

    public enum Worker: Int, FiniteDomainKey {
        case one = 1, two = 2

        public static var defaultValue: Self { .one }
        public static let formalDomain: [Self] = [.one, .two]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.parallel-reachable.worker")
        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case a, b, c
    }

    public static var spec: TLASpec {
        #spec("ParallelReachability") {
            Extends(.finiteSets)
            Algorithm("ParallelReachability", scoped: { scope in
                let nodes = SetExpr<Node>.literal(.one, .two, .three, .four)
                let successors = Select(
                    from: Where(Functions(from: Node.all, to: Subsets(of: nodes))) { graph in
                        All(Node.all) { node in graph[node].cardinality == 2 }
                    },
                    matching: { graph in graph.expr == graph.expr }
                )
                let marked = scope.sharedVar("marked", initial: SetExpr<Node>())
                let frontier = scope.sharedVar("frontier", initial: SetExpr<Node>.literal(.one))

                Each(Worker.all, fairness: .weak, scoped: { _, scope in
                    let current: LocalVariable<Node> = scope.localVar("current", initial: .one)
                    let pending: LocalVariable<SetExpr<Node>> = scope.localVar("pending", initial: SetExpr<Node>())

                    Do(Step.a) {
                        Either {
                            When(!frontier.isEmpty)
                            With(frontier) { node in
                                Assign(current, to: node)
                            }
                            Goto(Step.b)
                        } or: {
                            When(frontier.isEmpty)
                            Stop()
                        }
                    }

                    Do(Step.b) {
                        If(!marked.contains(current.expr)) {
                            Assign(marked, to: marked.inserting(current.expr))
                            Assign(pending, to: successors[current])
                            Goto(Step.c)
                        } else: {
                            Assign(frontier, to: frontier.removing(current.expr))
                            Goto(Step.a)
                        }
                    }

                    Do(Step.c) {
                        Either {
                            When(!pending.expr.isEmpty)
                            With(pending) { node in
                                Assign(frontier, to: frontier.inserting(node))
                                Assign(pending, to: pending.expr.removing(node))
                            }
                            Goto(Step.c)
                        } or: {
                            When(pending.expr.isEmpty)
                            Goto(Step.a)
                        }
                    }
                })

                Invariant("TypeOK") {
                    marked.isSubset(of: SetExpr<Node>.literal(.one, .two, .three, .four))
                    frontier.isSubset(of: SetExpr<Node>.literal(.one, .two, .three, .four))
                }
            })
        }
    }
}

extension Example {
    /// A bounded source port of `MCParReach` with the published finite
    /// process and graph constraints. Its native count is pinned here;
    /// external TLC graph comparison remains separate evidence.
    public static let parallelReachable = Entry(
        id: "MisraReachability/ParReach",
        upstreamSpec: "MisraReachability",
        upstreamModule: "specifications/MisraReachability/ParReach.tla",
        upstreamCfg: "specifications/MisraReachability/MCParReach.cfg",
        expectedDistinct: 393,
        spec: ParallelReachableModel.spec,
        notes: "Bounded source port with four nodes, two workers, and a static two-successors-per-node graph selection."
    )
}
