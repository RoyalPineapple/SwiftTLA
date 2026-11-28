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
        case probeMidpointOrFinish = "a"
    }

    package static var spec: TLASpec {
        #spec("BinarySearch") { model in
            Extends(.integers)
            let values = model.parameter(tlaName: "Values", as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([1, 2, 3, 4, 5])]))
            let maximumSequenceLength = model.parameter(tlaName: "MaxSeqLen", as: Int.self, in: 8...8)
            let Termination = Temporal()
            Algorithm("BinarySearch", fairness: .weak) { scope in
                let sortedValues = scope.sharedVar(tlaName: "seq", initiallyIn: SortedSequences(
                    of: values,
                    lengths: IntRange(1, through: maximumSequenceLength)
                ))
                let searchValue = scope.sharedVar(tlaName: "val", initiallyIn: values)
                let low = scope.sharedVar(initial: 1)
                let high: SharedVariable<Int> = scope.sharedVar(initial: sortedValues.count)
                let result = scope.sharedVar(initial: 0)

                While(Step.probeMidpointOrFinish, low <= high && result == 0) {
                    Let((low + high).integerDivided(by: 2)) { mid in
                        Let(sortedValues[mid.expr]) { middleValue in
                            If(middleValue == searchValue) {
                                result.set(mid.expr)
                            } else: {
                                If(searchValue < middleValue) {
                                    high.set(mid.expr - 1)
                                } else: {
                                    low.set(mid.expr + 1)
                                }
                            }
                        }
                    }
                }

                let typeOK = sortedValues.count >= 1 && sortedValues.count <= maximumSequenceLength
                    && IntRange(1, through: sortedValues.count).allSatisfy { index in
                        values.contains(sortedValues[index])
                            && IntRange(index + 1, through: sortedValues.count).allSatisfy { other in
                                sortedValues[index] <= sortedValues[other]
                            }
                    }
                    && values.contains(searchValue)
                    && low >= 1 && low <= sortedValues.count + 1
                    && high >= 0 && high <= sortedValues.count
                    && result >= 0 && result <= sortedValues.count
                Invariant("TypeOK") { typeOK }
                let containsValue = sortedValues.contains(searchValue)
                Invariant("Inv") {
                    typeOK
                    result == 0 || (sortedValues.count > 0 && sortedValues[result] == searchValue)
                    Finished() || If(
                        containsValue,
                        then: IntRange(low, through: high).contains { index in sortedValues[index] == searchValue },
                        else: result == 0
                    )
                    !Finished() || result != 0
                        || !containsValue
                }
                Invariant("resultCorrect") {
                    (!Finished()) || If(
                        containsValue,
                        then: sortedValues[result] == searchValue,
                        else: result == 0
                    )
                }
                Termination(.eventually(Finished()))
            }
            Validation("MCBinarySearch") {
                Bind(values, to: Set<Int>([1, 2, 3, 4, 5]))
                Bind(maximumSequenceLength, to: 8)
            }
        }
    }
}
