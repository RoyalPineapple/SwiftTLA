import SwiftTLA
import SwiftTLAMacros

/// Boyer–Moore majority voting, with the upstream MCMajority configuration.
@TLAModel
package struct MajorityModel: Sendable {
    package enum Element: String, CaseIterable, FiniteTLAValueDomain {
        case A, B, C
        package static var defaultValue: Self { .A }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Step: String, CaseIterable { case Next }

    package static var spec: TLASpec {
        #spec("Majority") { scope in
            Extends(.integers, .sequences, .finiteSets)
            let Value = scope.parameter(as: Set<Element>.self,
                in: Set<Set<Element>>([Set<Element>([Element.A, Element.B, Element.C])]))
            let bound = scope.parameter(as: Int.self, in: 0...5)
            Assume(Value.cardinality > 0 && bound >= 0)
            let seq = scope.sharedVar(in: Sequences(of: Value, lengths: IntRange(0, through: bound)))
            let i = scope.sharedVar(initial: 1)
            let cand = scope.sharedVar(in: Value)
            let cnt = scope.sharedVar(initial: 0)

            let TypeOK = Invariant()
            let Correct = Invariant()
            let Inv = Invariant()
            Do(Step.Next) {
                When(i <= seq.count)
                If(cnt == 0) {
                    Assign(cand, to: seq[i])
                    Assign(cnt, to: 1)
                } else: {
                    If(cand == seq[i]) { Assign(cnt, to: cnt + 1) }
                    else: { Assign(cnt, to: cnt - 1) }
                }
                Assign(i, to: i + 1)
            }
            WeakFairnessNext()

            TypeOK {
                seq.count <= bound && i >= 1 && i <= seq.count + 1 && cnt >= 0
                    && Value.contains(cand)
                    && ForAll(in: IntRange(1, through: seq.count)) { index in
                        Value.contains(seq[index.expr])
                    }
            }
            Correct {
                i <= seq.count || ForAll(in: Value) { value in
                    2 * IntRange(1, through: seq.count).filtering { index in
                        seq[index.expr] == value
                    }.cardinality <= seq.count || value == cand
                }
            }
            let candidateOccurrences = IntRange(1, through: i - 1).filtering { index in
                seq[index.expr] == cand
            }.cardinality
            Inv {
                cnt <= candidateOccurrences
                    && 2 * (candidateOccurrences - cnt) <= i - 1 - cnt
                    && ForAll(in: Value) { value in
                        value == cand || 2 * IntRange(1, through: i - 1).filtering { index in
                            seq[index.expr] == value
                        }.cardinality <= i - 1 - cnt
                    }
            }
            Validation("MCMajority") {
                Bind(Value, to: Set<Element>([Element.A, Element.B, Element.C]))
                Bind(bound, to: 5)
            }.checkingDeadlock(false)
        }
    }
}
