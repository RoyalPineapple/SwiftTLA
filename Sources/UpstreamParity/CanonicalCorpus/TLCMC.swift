import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TLCMCModel: Sendable {
    package enum Node: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1
        case two = 2
        case three = 3
        case four = 4

        package static var defaultValue: Self { .one }
        package static let finiteValues: [Self] = [.one, .two, .three, .four]
    }

    package enum EmptyNode: String, TLAValueType {
        case value = "null"

        package static var defaultValue: Self { .value }
    }

    package typealias SearchNode = OneOf<Node, EmptyNode>

    private enum Step: String, CaseIterable {
        case scanInitialStates
        case checkInitialStates
        case dequeue
        case exploreSuccessors
        case trace
    }

    package static let corpusEntry = CanonicalCorpusEntry(
        id: "tlcmc-graph-1",
        specification: { TLCMCModel.spec },
        swiftConfiguration: .init(),
        plusCalConfiguration: .init()
    )

    package static var spec: TLASpec {
        #spec("TLCMC") {
            Extends(.integers, .sequences)
            Algorithm("ModelChecker", fairness: .weak, scoped: { scope in
                let initialStates = SetExpr<Node>.literal(.one, .two)
                let violations = SetExpr<Node>.literal(.four)
                let transitionTargets = Function<Node, SetExpr<Node>>.literal(
                    (.one, SetExpr<Node>.literal(.two)),
                    (.two, SetExpr<Node>.literal(.one, .three)),
                    (.three, SetExpr<Node>.literal(.four)),
                    (.four, SetExpr<Node>.literal(.three))
                )
                let frontier = scope.sharedVar(
                    "frontier",
                    in: SetExpr<TupleExpr<Node>>.literal(
                        TupleExpr<Node>.literal(Node.one, Node.two),
                        TupleExpr<Node>.literal(Node.two, Node.one)
                    )
                )
                let closed = scope.sharedVar("closed", initial: SetExpr<Node>())
                let currentState: SharedVariable<SearchNode> = scope.sharedVar(
                    "currentState",
                    initial: SearchNode.second(.value)
                )
                let successors = scope.sharedVar("successors", initial: SetExpr<Node>())
                let initialIndex = scope.sharedVar("initialIndex", initial: 1)
                let counterexample = scope.sharedVar("counterexample", initial: TupleExpr<Node>())
                let predecessorEdges = scope.sharedVar("predecessorEdges", initial: TupleExpr<Pair<Node, Node>>())
                let levels: SharedVariable<PartialFunction<Node, Int>> = scope.sharedVar(
                    "levels", initial: PartialFunction<Node, Int>.empty
                )

                While(Step.scanInitialStates, initialIndex <= frontier.expr.count) {
                    let initial = frontier.expr.at(initialIndex.expr)
                    Assign(currentState, to: SearchNode.first(initial))
                    Assign(closed, to: closed.inserting(initial))
                    Assign(levels, to: levels.updating(initial, to: 0))
                    Assign(initialIndex, to: initialIndex + 1)
                    If(violations.contains(initial)) {
                        Assign(counterexample, to: TupleExpr<Node>.literal(initial))
                        Goto(Step.trace)
                    }
                }

                Do(Step.checkInitialStates) {
                    Assert(closed.expr == initialStates)
                }

                Do(Step.dequeue) {
                    If(frontier.expr.count == 0) {
                        Stop()
                    } else: {
                        let current = frontier.at(1)
                        let nonSelfSuccessors = transitionTargets[current].removing(current)
                        Assign(currentState, to: SearchNode.first(current))
                        Assign(frontier, to: frontier.expr.removing(at: 1))
                        Assign(successors, to: nonSelfSuccessors.subtracting(closed.expr))
                        If(nonSelfSuccessors.cardinality == 0) {
                            Assign(counterexample, to: TupleExpr<Node>.literal(current))
                            Goto(Step.trace)
                        } else: {
                            Goto(Step.exploreSuccessors)
                        }
                    }
                }

                Do(Step.exploreSuccessors) {
                    If(successors.expr.isEmpty) {
                        Goto(Step.dequeue)
                    } else: {
                        With(successors) { successor in
                            let current = currentState.expr.assumingFirst(Node.self)
                            Assign(successors, to: successors.removing(successor.expr))
                            Assign(closed, to: closed.inserting(successor.expr))
                            Assign(frontier, to: frontier.expr.appending(successor.expr))
                            Assign(
                                predecessorEdges,
                                to: predecessorEdges.expr.appending(Pair<Node, Node>.literal(current, successor.expr))
                            )
                            Assign(levels, to: levels.updating(successor.expr, to: levels[current] + 1))
                            If(violations.contains(successor)) {
                                Assign(counterexample, to: TupleExpr<Node>.literal(current, successor.expr))
                                Goto(Step.trace)
                            } else: {
                                Goto(Step.exploreSuccessors)
                            }
                        }
                    }
                }

                While(Step.trace, true) {
                    If(initialStates.contains(counterexample.expr.head())) {
                        Assert(counterexample.expr.count > 0)
                        Stop()
                    } else: {
                        let predecessor = predecessorEdges.expr
                            .selecting { edge in edge.second() == counterexample.at(1) }
                            .at(1)
                            .first()
                        Assign(
                            counterexample,
                            to: TupleExpr<Node>.literal(predecessor).concatenating(counterexample.expr)
                        )
                        Goto(Step.trace)
                    }
                }

                Invariant("TypeOK") {
                    closed.expr.isSubset(of: SetExpr<Node>.literal(.one, .two, .three, .four))
                }
                Invariant("BFSLevel") { initialIndex >= 1 }
            })
        }
    }
}
