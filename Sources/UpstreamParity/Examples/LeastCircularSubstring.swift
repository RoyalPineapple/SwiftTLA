import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct LeastCircularSubstringModel: Sendable {
    package enum Step: String, CaseIterable {
        case L3, L5, L6, L7, L8, L9, L10, L11, L12, L13, L14, LVR
    }

    package static var spec: TLASpec {
        #spec("MCLeastCircularSubstring") { scope in
            let CharSetSize = scope.parameter(as: Int.self, in: 0...3)
            let MaxStringLength = scope.parameter(as: Int.self, in: 0...8)
            let TypeInvariant = Invariant()
            let Correctness = Invariant()
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: MaxStringLength))
            Algorithm("LeastCircularSubstring", scoped: { algorithm in
                let b = algorithm.sharedVar(in: ZSequences.sequences(over: IntRange(0, through: CharSetSize - 1)))
                let n = algorithm.sharedVar(initial: ZSequences.length(of: b))
                let f = algorithm.sharedVar(initial: Dictionary<Int, Int>.mapping(
                    over: IntRange(0, through: n * 2)) { _ in -1 })
                let i = algorithm.sharedVar(initial: -1)
                let j = algorithm.sharedVar(initial: 1)
                let k = algorithm.sharedVar(initial: 0)

                Do(Step.L3) {
                    If(j < n * 2) { Goto(Step.L5) } else: { Stop() }
                }
                Do(Step.L5) { Assign(i, to: f[j - k - 1]) }
                Do(Step.L6) {
                    If(b[j % n] != b[(k + i + 1) % n] && i != -1) {
                        Goto(Step.L7)
                    } else: { Goto(Step.L10) }
                }
                Do(Step.L7) {
                    If(b[j % n] < b[(k + i + 1) % n]) {
                        Goto(Step.L8)
                    } else: { Goto(Step.L9) }
                }
                Do(Step.L8) { Assign(k, to: j - i - 1) }
                Do(Step.L9) {
                    Assign(i, to: f[i])
                    Goto(Step.L6)
                }
                Do(Step.L10) {
                    If(b[j % n] != b[(k + i + 1) % n] && i == -1) {
                        Goto(Step.L11)
                    } else: { Goto(Step.L14) }
                }
                Do(Step.L11) {
                    If(b[j % n] < b[(k + i + 1) % n]) {
                        Goto(Step.L12)
                    } else: { Goto(Step.L13) }
                }
                Do(Step.L12) { Assign(k, to: j) }
                Do(Step.L13) {
                    Assign(f[j - k], to: -1)
                    Goto(Step.LVR)
                }
                Do(Step.L14) { Assign(f[j - k], to: i + 1) }
                Do(Step.LVR) {
                    Assign(j, to: j + 1)
                    Goto(Step.L3)
                }

                TypeInvariant {
                    ZSequences.sequences(over: IntRange(0, through: CharSetSize - 1)).contains(b)
                        && n == ZSequences.length(of: b)
                        && Functions(from: IntRange(0, through: n * 2),
                            to: IntRange(0, through: n * 2).union(SetExpr<Int>.literal(-1))).contains(f)
                        && IntRange(0, through: n * 2).union(SetExpr<Int>.literal(-1)).contains(i)
                        && IntRange(0, through: n * 2).union(SetExpr<Int>.literal(1)).contains(j)
                        && ZSequences.indices(of: b).union(SetExpr<Int>.literal(0)).contains(k)
                }
                Correctness {
                    !Finished() || ForAll(in: ZSequences.rotations(of: b)) { other in
                        Expr<Bool>(ZSequences.lexicographicallyPrecedesOrEquals(
                            ZSequences.rotation(of: b, leftBy: k), other.seq))
                            && (ZSequences.rotation(of: b, leftBy: k) != other.seq || k <= other.shift)
                    }
                }
            })
            Validation("Small") {
                Bind(CharSetSize, to: 2)
                Bind(MaxStringLength, to: 6)
            }
            Validation("Medium") {
                Bind(CharSetSize, to: 3)
                Bind(MaxStringLength, to: 8)
            }
        }
    }
}
