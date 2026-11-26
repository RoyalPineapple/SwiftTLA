// Binary search narrows an interval in a sorted sequence until it finds the target or exhausts
// the interval.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/LoopInvariance/BinarySearch.tla

import SwiftTLA
import SwiftTLAMacros

/// The published bounded PlusCal binary-search model.
///
/// The input is an assumption: `seq` is selected from the finite set of
/// nondecreasing sequences. The `While` body is the source's one labeled
/// atomic step, including its two scoped `with` bindings.
@TLAModel
package struct BinarySearchModel: Sendable {
    private enum Step: String, CaseIterable {
        case a
    }

    package static var spec: TLASpec {
        #spec("BinarySearch") { model in
            Extends(.integers)
            let Values = model.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([1, 2, 3, 4, 5])]))
            let MaxSeqLen = model.parameter(as: Int.self, in: 8...8)
            let Termination = Temporal()
            Algorithm("BinarySearch", fairness: .weak) { scope in
                let seq = scope.sharedVar(initiallyIn: SortedSequences(
                    of: Values,
                    lengths: IntRange(1, through: MaxSeqLen)
                ))
                let val = scope.sharedVar(initiallyIn: Values)
                let low = scope.sharedVar(initial: 1)
                let high: SharedVariable<Int> = scope.sharedVar(initial: seq.count)
                let result = scope.sharedVar(initial: 0)

                While(Step.a, low <= high && result == 0) {
                    Let((low + high).integerDivided(by: 2)) { mid in
                        Let(seq[mid.expr]) { middleValue in
                            If(middleValue == val) {
                                result.set(mid.expr)
                            } else: {
                                If(val < middleValue) {
                                    high.set(mid.expr - 1)
                                } else: {
                                    low.set(mid.expr + 1)
                                }
                            }
                        }
                    }
                }

                let typeOK = seq.count >= 1 && seq.count <= MaxSeqLen
                    && IntRange(1, through: seq.count).allSatisfy { index in
                        Values.contains(seq[index])
                            && IntRange(index + 1, through: seq.count).allSatisfy { other in
                                seq[index] <= seq[other]
                            }
                    }
                    && Values.contains(val)
                    && low >= 1 && low <= seq.count + 1
                    && high >= 0 && high <= seq.count
                    && result >= 0 && result <= seq.count
                Invariant("TypeOK") { typeOK }
                let containsValue = seq.contains(val)
                Invariant("Inv") {
                    typeOK
                    result == 0 || (seq.count > 0 && seq[result] == val)
                    Finished() || If(
                        containsValue,
                        then: IntRange(low, through: high).contains { index in seq[index] == val },
                        else: result == 0
                    )
                    !Finished() || result != 0
                        || !containsValue
                }
                Invariant("resultCorrect") {
                    (!Finished()) || If(
                        containsValue,
                        then: seq[result] == val,
                        else: result == 0
                    )
                }
                Termination(.eventually(Finished()))
            }
            Validation("MCBinarySearch") {
                Bind(Values, to: Set<Int>([1, 2, 3, 4, 5]))
                Bind(MaxSeqLen, to: 8)
            }
        }
    }
}
