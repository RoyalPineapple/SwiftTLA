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
    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("Spanning") { scope in
            Extends(.integers)
            let Proc = scope.parameter(as: Set<Int>.self, in: Subsets(of: Set<Int>([1, 2, 3])))
            let NoPrnt = scope.parameter(as: MissingParent.self, in: Set<MissingParent>([.none]))
            let root = scope.parameter(as: Int.self, in: Proc)
            let pairs = Proc.flatMapping { (i: WithValue<Int>) in
                Proc.mapping { (j: WithValue<Int>) in Pair<Int, Int>.literal(i, j) }
            }
            let nbrs = scope.parameter(as: Set<Pair<Int, Int>>.self, in: Subsets(of: pairs))
            Assume(nbrs.isSubset(of: pairs))
            let missing = Parent.second(NoPrnt)
            let prnt: SharedVariable<[Int: Parent]> = scope.sharedVar(initial:
                Dictionary<Int, Parent>.mapping(over: Proc) { _ in missing })
            let rpt = scope.sharedVar(initial: Dictionary<Int, Bool>.mapping(over: Proc) { _ in false })
            let msg = scope.sharedVar(initial: Set<Pair<Int, Int>>())

            Do(Step.next) {
                With(Proc, Proc) { i, j in
                    If(i != root && prnt[i] == missing && msg.contains(Pair<Int, Int>.literal(j, i))) {
                        prnt[i].set(Parent.first(j))
                    } else: {
                        Either {
                            When(i == root || prnt[i] != missing) {
                                With(Proc) { k in
                                    let link = Pair<Int, Int>.literal(i, k)
                                    When(nbrs.contains(link) && !msg.contains(link))
                                    msg.insert(link)
                                }
                            }
                            When(prnt[i] != missing && !rpt[i]) { rpt[i].set(true) }
                            When(true) { Skip() }
                        }
                    }
                }
            }
            WeakFairnessNext()

            let typeOK = Invariant("TypeOK") {
                Proc.allSatisfy { i in
                    prnt[i] == missing || Proc.contains { j in
                        prnt[i] == Parent.first(j) && nbrs.contains(Pair<Int, Int>.literal(i, j))
                    }
                }
                Functions(from: Proc, to: Bool.all).contains(rpt)
                msg.isSubset(of: pairs)
            }
            typeOK
            Invariant("SntMsg") {
                Proc.allSatisfy { i in
                    i == root || prnt[i] != missing
                        || Proc.allSatisfy { j in !msg.contains(Pair<Int, Int>.literal(i, j)) }
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
