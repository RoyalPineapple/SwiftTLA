// Messages spread from a root through a network to build a spanning tree.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/spanning/spanning.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SpanningModel: Sendable {
    package enum MissingParent: String, CaseIterable, FiniteTLAValueDomain {
        case none = "NoPrnt"
        package static var defaultValue: Self { .none }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package typealias Parent = OneOf<Int, MissingParent>
    private enum Step: String, CaseIterable { case takeSpanningTreeStep = "Next" }

    package static var spec: TLASpec {
        #spec("Spanning") { scope in
            Extends(.integers)
            let Proc = scope.parameter(as: Set<Int>.self, in: Subsets(of: Set<Int>([1, 2, 3])))
            let NoPrnt = scope.parameter(as: MissingParent.self, in: Set<MissingParent>([.none]))
            let root = scope.parameter(as: Int.self, in: Proc)
            let pairs = Proc.flatMapping { (source: WithValue<Int>) in
                Proc.mapping { (destination: WithValue<Int>) in Pair<Int, Int>.literal(source, destination) }
            }
            let nbrs = scope.parameter(as: Set<Pair<Int, Int>>.self, in: Subsets(of: pairs))
            Assume(nbrs.isSubset(of: pairs))
            let missing = Parent.second(NoPrnt)
            let prnt: SharedVariable<[Int: Parent]> = scope.sharedVar(initial:
                Dictionary<Int, Parent>.mapping(over: Proc) { _ in missing })
            let rpt = scope.sharedVar(initial: Dictionary<Int, Bool>.mapping(over: Proc) { _ in false })
            let msg = scope.sharedVar(initial: Set<Pair<Int, Int>>())

            Do(Step.takeSpanningTreeStep) {
                With(Proc, Proc) { node, candidateParent in
                    let incomingMessage = Pair<Int, Int>.literal(candidateParent, node)
                    If(node != root && prnt[node] == missing && msg.contains(incomingMessage)) {
                        prnt[node].set(Parent.first(candidateParent))
                    } else: {
                        Either {
                            When(node == root || prnt[node] != missing) {
                                With(Proc) { destination in
                                    let link = Pair<Int, Int>.literal(node, destination)
                                    When(nbrs.contains(link) && !msg.contains(link))
                                    msg.insert(link)
                                }
                            }
                            When(prnt[node] != missing && !rpt[node]) { rpt[node].set(true) }
                            When(true) { Skip() }
                        }
                    }
                }
            }
            WeakFairnessNext()

            let typeOK = Invariant("TypeOK")
            typeOK {
                Proc.allSatisfy { node in
                    prnt[node] == missing || Proc.contains { parent in
                        prnt[node] == Parent.first(parent) && nbrs.contains(Pair<Int, Int>.literal(node, parent))
                    }
                }
                Functions(from: Proc, to: Bool.all).contains(rpt)
                msg.isSubset(of: pairs)
            }
            Invariant("SntMsg") {
                Proc.allSatisfy { node in
                    node == root || prnt[node] != missing
                        || Proc.allSatisfy { destination in !msg.contains(Pair<Int, Int>.literal(node, destination)) }
                }
            }
            Validation("broadcast") {
                Bind(Proc, to: Set<Int>([1, 2, 3]))
                Bind(NoPrnt, to: MissingParent.none)
                Bind(root, to: 1)
                Bind(nbrs, to: Set<Pair<Int, Int>>([Pair(first: 1, second: 2), Pair(first: 1, second: 3)]))
            }.expect(typeOK, .violated)
        }
    }
}
