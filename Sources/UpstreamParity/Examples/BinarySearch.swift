import SwiftTLA
import SwiftTLAMacros

/// The published bounded PlusCal binary-search model.
///
/// The input is an assumption: `seq` is selected from the finite set of
/// nondecreasing sequences. The `While` body is the source's one labeled
/// atomic step, including its two scoped `with` bindings.
package struct BinarySearchModel: Sendable {
    private enum Step: String, CaseIterable {
        case a
    }

    package static var spec: TLASpec {
        #spec("BinarySearch") {
            Extends(.integers)
            Algorithm("BinarySearch", fairness: .weak, scoped: { scope in
                let seq = scope.sharedVar("seq", in: SortedSequences(
                    of: SetExpr<Int>.literal(1, 2, 3, 4, 5),
                    lengths: 0...8
                ))
                let val = scope.sharedVar("val", in: SetExpr<Int>.literal(1, 2, 3, 4, 5))
                let low = scope.sharedVar("low", initial: 1)
                let high: SharedVariable<Int> = scope.sharedVar("high", initial: seq.count)
                let result = scope.sharedVar("result", initial: 0)

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

                Invariant("TypeOK") {
                    val >= 1 && val <= 5
                    low >= 1 && low <= seq.count + 1
                    high >= 0 && high <= seq.count
                    result >= 0 && result <= seq.count
                }
                Invariant("resultCorrect") {
                    (!Finished()) || If(
                        Exists(in: IntRange(1, through: seq.count)) { index in
                            seq[index.expr] == val
                        },
                        then: seq[result] == val,
                        else: result == 0
                    )
                }
            })
        }
    }
}

extension Example {
    package static let binarySearch = Entry(
        id: "LoopInvariance/BinarySearch",
        upstreamSpec: "LoopInvariance",
        upstreamModule: "specifications/LoopInvariance/BinarySearch.tla",
        upstreamCfg: "specifications/LoopInvariance/MCBinarySearch.cfg",
        expectedDistinct: 27_963,
        maximumStateLimit: 100_000,
        spec: BinarySearchModel.spec,
        notes: "Published BinarySearch with Values = 1...5 and MaxSeqLen = 8."
    )
}
