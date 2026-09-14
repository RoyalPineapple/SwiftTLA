import SwiftTLA
import SwiftTLAMacros

/// Boyer–Moore majority voting, with the upstream MCMajority configuration.
@TLAModel
package struct MajorityModel: Sendable {
    package enum Value: String, CaseIterable, FiniteTLAValueDomain {
        case A, B, C
        package static var defaultValue: Self { .A }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package static var spec: TLASpec {
        #spec("Majority") { scope in
            Extends(.integers, .sequences, .finiteSets)
            let seq = scope.sharedVar("seq", in: Sequences(of: Value.all, lengths: 0...5))
            let i = scope.sharedVar("i", initial: 1)
            let cand = scope.sharedVar("cand", in: Value.all)
            let cnt = scope.sharedVar("cnt", initial: 0)

            let next = SwiftTLA.Action("Next") {
                i <= seq.count && i.becomes(i + 1)
                    && ((cnt == 0 && cand.becomes(seq[i]) && cnt.becomes(1))
                        || (cnt != 0 && cand == seq[i] && cnt.becomes(cnt + 1))
                        || (cnt != 0 && cand != seq[i] && cnt.becomes(cnt - 1)))
            }
            next
            WeakFairness(next)

            Invariant("TypeOK") {
                seq.count <= 5 && i >= 1 && i <= seq.count + 1 && cnt >= 0
                    && Value.all.contains(cand)
                    && ForAll(in: IntRange(1, through: seq.count)) { index in
                        Value.all.contains(seq[index.expr])
                    }
            }
            Invariant("Correct") {
                i <= seq.count || ForAll(in: Value.all) { value in
                    2 * IntRange(1, through: seq.count).filtering { index in
                        seq[index.expr] == value
                    }.cardinality <= seq.count || value == cand
                }
            }
            let candidateOccurrences = IntRange(1, through: i - 1).filtering { index in
                seq[index.expr] == cand
            }.cardinality
            Invariant("Inv") {
                cnt <= candidateOccurrences
                    && 2 * (candidateOccurrences - cnt) <= i - 1 - cnt
                    && ForAll(in: Value.all) { value in
                        value == cand || 2 * IntRange(1, through: i - 1).filtering { index in
                            seq[index.expr] == value
                        }.cardinality <= i - 1 - cnt
                    }
            }
        }
    }
}

extension Example {
    package static let majority = FiniteModelFixture(
        expectedDistinct: 2733, maximumStateLimit: 10_000, spec: MajorityModel.spec)
}
