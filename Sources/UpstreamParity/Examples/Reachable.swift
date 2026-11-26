// A work list discovers all nodes reachable from the starting node.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/MisraReachability/Reachable.tla

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
            Algorithm("Reachable", fairness: .weak) { scope in
                let nodes = SetExpr<Node>.literal(.one, .two, .three, .four)
                let successors = Select(
                    from: Where(Functions(from: Node.all, to: Subsets(of: nodes))) { graph in
                        Node.all.allSatisfy { node in
                            graph[node].count == 2
                        }
                    },
                    matching: { graph in graph.expr == graph.expr }
                )
                let marked = scope.sharedVar(initial: SetExpr<Node>())
                let frontier = scope.sharedVar(initial: SetExpr<Node>.literal(.one))

                While(Step.a, !frontier.isEmpty) {
                    With(frontier) { node in
                        If(!marked.contains(node)) {
                            marked.insert(node)
                            frontier.formUnion(successors[node])
                        } else: {
                            frontier.remove(node)
                        }
                    }
                }

                Invariant("TypeOK") {
                    marked.isSubset(of: SetExpr<Node>.literal(.one, .two, .three, .four))
                    frontier.isSubset(of: SetExpr<Node>.literal(.one, .two, .three, .four))
                    (!Finished()) || frontier.isEmpty
                }
                Eventually("EventuallyFinished", Finished())
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
