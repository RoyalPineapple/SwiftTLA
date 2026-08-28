import SwiftTLA
import SwiftTLAMacros

/// A bounded source port of Misra's reachable-node algorithm.
///
/// The upstream TLC configuration chooses a four-node graph in which every
/// node has exactly two successors. This model makes that configuration a
/// static formal choice, then runs the published work-list algorithm.
@TLAModel
package struct ReachableModel: Sendable {
    package enum Node: Int, FiniteTLAValueDomain {
        case one = 1
        case two = 2
        case three = 3
        case four = 4

        package static var defaultValue: Self { .one }
        package static let finiteValues: [Self] = [.one, .two, .three, .four]

        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case a
    }

    package static var spec: TLASpec {
        #spec("Reachable") {
            Extends(.finiteSets)
            Extends(.integers)
            Algorithm("Reachable", fairness: .weak, scoped: { scope in
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
                Eventually("EventuallyFinished", Finished())
            })
        }
    }
}

extension Example {
    /// The static graph selection matches the published configuration shape.
    /// This native count is not an upstream-TLC parity claim: TLC's `CHOOSE`
    /// ordering is an external implementation detail that still needs a graph
    /// comparison before this entry can be marked as parity-validated.
    package static let reachable = FiniteModelFixture(
        expectedDistinct: 8,
        maximumStateLimit: 50_000,
        spec: ReachableModel.spec,
    )
}
