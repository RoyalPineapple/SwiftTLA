// Boyer–Moore majority voting scans a sequence while updating a candidate and a count.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/Majority/Majority.tla

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
    package enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("Majority") { scope in
            Extends(.integers, .sequences, .finiteSets)
            let Value = scope.parameter(as: Set<Element>.self,
                in: Set<Set<Element>>([Set<Element>([Element.A, Element.B, Element.C])]))
            let bound = scope.parameter(as: Int.self, in: 0...5)
            Assume(Value.count > 0 && bound >= 0)
            let seq = scope.sharedVar(initiallyIn: Sequences(of: Value, lengths: IntRange(0, through: bound)))
            let i = scope.sharedVar(initial: 1)
            let cand = scope.sharedVar(initiallyIn: Value)
            let cnt = scope.sharedVar(initial: 0)

            Do(Step.next, when: i <= seq.count) {
                If(cnt == 0) {
                    cand.set(seq[i])
                    cnt.set(1)
                } else: {
                    If(cand == seq[i]) { cnt += 1 }
                    else: { cnt.set(cnt - 1) }
                }
                i += 1
            }
            WeakFairnessNext()

            Invariant("TypeOK") {
                seq.count <= bound && i >= 1 && i <= seq.count + 1 && cnt >= 0
                    && Value.contains(cand)
                    && IntRange(1, through: seq.count).allSatisfy { index in
                        Value.contains(seq[index.expr])
                    }
            }
            Invariant("Correct") {
                i <= seq.count || Value.allSatisfy { value in
                    2 * IntRange(1, through: seq.count).filter { index in
                        seq[index.expr] == value
                    }.count <= seq.count || value == cand
                }
            }
            let candidateOccurrences = IntRange(1, through: i - 1).filter { index in
                seq[index.expr] == cand
            }.count
            Invariant("Inv") {
                cnt <= candidateOccurrences
                    && 2 * (candidateOccurrences - cnt) <= i - 1 - cnt
                    && Value.allSatisfy { value in
                        value == cand || 2 * IntRange(1, through: i - 1).filter { index in
                            seq[index.expr] == value
                        }.count <= i - 1 - cnt
                    }
            }
            Validation("MCMajority") {
                Bind(Value, to: Set<Element>([Element.A, Element.B, Element.C]))
                Bind(bound, to: 5)
            }.checkingDeadlock(false)
        }
    }
}
