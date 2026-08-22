import SwiftTLA
import SwiftTLAMacros

/// A bounded source port of Misra's reachable-node algorithm.
///
/// The upstream TLC configuration chooses a four-node graph in which every
/// node has exactly two successors. This model makes that configuration a
/// static formal choice, then runs the published work-list algorithm.
@TLAModel
public struct ReachableModel: Sendable {
    public enum Node: Int, FiniteDomainKey {
        case one = 1
        case two = 2
        case three = 3
        case four = 4

        public static var defaultValue: Self { .one }
        public static let formalDomain: [Self] = [.one, .two, .three, .four]
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.reachable.node")

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case a
    }

    public static var spec: TLASpec {
        #spec("Reachable") {
            Extends(.finiteSets)
            Extends(.integers)
            Algorithm("Reachable") { scope in
                let nodes = SetExpr<Node>.literal(.one, .two, .three, .four)
                let successors = Select(
                    from: Where(Functions(from: Node.all, to: Subsets(of: nodes))) { graph in
                        All(Node.all) { node in
                            graph[node].cardinality == 2
                        }
                    },
                    matching: { graph in graph.expr == graph.expr }
                )
                let marked = scope.sharedVar("marked", initial: SetExpr<Node>())
                let frontier = scope.sharedVar("frontier", initial: SetExpr<Node>.literal(.one))

                While(Step.a, !frontier.isEmpty) {
                    With(frontier) { node in
                        If(!marked.contains(node)) {
                            Assign(marked, to: marked.inserting(node))
                            Assign(frontier, to: frontier.expr.union(successors[node]))
                        } else: {
                            Assign(frontier, to: frontier.removing(node))
                        }
                    }
                }

                Invariant("TypeOK") {
                    marked.isSubset(of: SetExpr<Node>.literal(.one, .two, .three, .four))
                    frontier.isSubset(of: SetExpr<Node>.literal(.one, .two, .three, .four))
                    (!Finished()) || frontier.isEmpty
                }
                WeakFairnessNext()
                Eventually("EventuallyFinished", Finished())
            }
        }
    }
}

extension Example {
    /// The static graph selection matches the published configuration shape.
    /// This native count is not an upstream-TLC parity claim: TLC's `CHOOSE`
    /// ordering is an external implementation detail that still needs a graph
    /// comparison before this entry can be marked as parity-validated.
    public static let reachable = Entry(
        id: "MisraReachability/Reachable",
        upstreamSpec: "MisraReachability",
        upstreamModule: "specifications/MisraReachability/Reachable.tla",
        upstreamCfg: "specifications/MisraReachability/MCReachable.cfg",
        expectedDistinct: 8,
        spec: ReachableModel.spec,
        notes: "Bounded source port with the published four-node, two-successor graph constraint; native count pinned pending external TLC graph comparison."
    )
}
