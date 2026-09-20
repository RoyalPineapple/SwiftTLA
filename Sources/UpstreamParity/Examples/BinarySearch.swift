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
            let resultCorrect = Invariant()
            let TypeOK = Invariant()
            let Inv = Invariant()
            let Termination = Temporal()
            Algorithm("BinarySearch", fairness: .weak, scoped: { scope in
                let seq = scope.sharedVar(in: SortedSequences(
                    of: Values,
                    lengths: IntRange(1, through: MaxSeqLen)
                ))
                let val = scope.sharedVar(in: Values)
                let low = scope.sharedVar(initial: 1)
                let high: SharedVariable<Int> = scope.sharedVar(initial: seq.count)
                let result = scope.sharedVar(initial: 0)

                While(Step.a, low <= high && result == 0) {
                    Let((low + high).integerDivided(by: 2)) { mid in
                        Let(seq[mid.expr]) { middleValue in
                            If(middleValue == val) {
                                Assign(result, to: mid.expr)
                            } else: {
                                If(val < middleValue) {
                                    Assign(high, to: mid.expr - 1)
                                } else: {
                                    Assign(low, to: mid.expr + 1)
                                }
                            }
                        }
                    }
                }

                let typeOK = seq.count >= 1 && seq.count <= MaxSeqLen
                    && ForAll(in: IntRange(1, through: seq.count)) { index in
                        Values.contains(seq[index])
                            && ForAll(in: IntRange(index + 1, through: seq.count)) { other in
                                seq[index] <= seq[other]
                            }
                    }
                    && Values.contains(val)
                    && low >= 1 && low <= seq.count + 1
                    && high >= 0 && high <= seq.count
                    && result >= 0 && result <= seq.count
                TypeOK { typeOK }
                Inv {
                    typeOK
                    result == 0 || (seq.count > 0 && seq[result] == val)
                    Finished() || If(
                        Exists(in: IntRange(1, through: seq.count)) { index in seq[index] == val },
                        then: Exists(in: IntRange(low, through: high)) { index in seq[index] == val },
                        else: result == 0
                    )
                    !Finished() || result != 0
                        || ForAll(in: IntRange(1, through: seq.count)) { index in seq[index] != val }
                }
                resultCorrect {
                    (!Finished()) || If(
                        Exists(in: IntRange(1, through: seq.count)) { index in
                            seq[index.expr] == val
                        },
                        then: seq[result] == val,
                        else: result == 0
                    )
                }
                Termination(.eventually(Finished()))
            })
            Validation("MCBinarySearch") {
                Bind(Values, to: Set<Int>([1, 2, 3, 4, 5]))
                Bind(MaxSeqLen, to: 8)
            }
        }
    }
}
