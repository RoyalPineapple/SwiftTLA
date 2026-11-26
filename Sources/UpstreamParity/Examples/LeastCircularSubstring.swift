// The algorithm finds the lexicographically least rotation of a circular sequence.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/LeastCircularSubstring/LeastCircularSubstring.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct LeastCircularSubstringModel: Sendable {
    package enum Step: String, CaseIterable {
        case l3 = "L3"
        case l5 = "L5"
        case l6 = "L6"
        case l7 = "L7"
        case l8 = "L8"
        case l9 = "L9"
        case l10 = "L10"
        case l11 = "L11"
        case l12 = "L12"
        case l13 = "L13"
        case l14 = "L14"
        case lvr = "LVR"
    }

    package static var spec: TLASpec {
        #spec("MCLeastCircularSubstring") { scope in
            let CharSetSize = scope.parameter(as: Int.self, in: 0...3)
            let MaxStringLength = scope.parameter(as: Int.self, in: 0...8)
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: MaxStringLength))
            let LeastCircularSubstring = Algorithm { algorithm in
                let b = algorithm.sharedVar(initiallyIn: ZSequences.sequences(over: IntRange(0, through: CharSetSize - 1)))
                let n = algorithm.sharedVar(initial: ZSequences.length(of: b))
                let f = algorithm.sharedVar(initial: Dictionary<Int, Int>.mapping(
                    over: IntRange(0, through: n * 2)) { _ in -1 })
                let i = algorithm.sharedVar(initial: -1)
                let j = algorithm.sharedVar(initial: 1)
                let k = algorithm.sharedVar(initial: 0)

                Do(Step.l3) {
                    If(j < n * 2) { Goto(Step.l5) } else: { Stop() }
                }
                Do(Step.l5) { i.set(f[j - k - 1]) }
                Do(Step.l6) {
                    If(b[j % n] != b[(k + i + 1) % n] && i != -1) {
                        Goto(Step.l7)
                    } else: { Goto(Step.l10) }
                }
                Do(Step.l7) {
                    If(b[j % n] < b[(k + i + 1) % n]) {
                        Goto(Step.l8)
                    } else: { Goto(Step.l9) }
                }
                Do(Step.l8) { k.set(j - i - 1) }
                Do(Step.l9) {
                    i.set(f[i])
                    Goto(Step.l6)
                }
                Do(Step.l10) {
                    If(b[j % n] != b[(k + i + 1) % n] && i == -1) {
                        Goto(Step.l11)
                    } else: { Goto(Step.l14) }
                }
                Do(Step.l11) {
                    If(b[j % n] < b[(k + i + 1) % n]) {
                        Goto(Step.l12)
                    } else: { Goto(Step.l13) }
                }
                Do(Step.l12) { k.set(j) }
                Do(Step.l13) {
                    f[j - k].set(-1)
                    Goto(Step.lvr)
                }
                Do(Step.l14) { f[j - k].set(i + 1) }
                Do(Step.lvr) {
                    j += 1
                    Goto(Step.l3)
                }

                Invariant("TypeInvariant") {
                    ZSequences.sequences(over: IntRange(0, through: CharSetSize - 1)).contains(b)
                        && n == ZSequences.length(of: b)
                        && Functions(from: IntRange(0, through: n * 2),
                            to: IntRange(0, through: n * 2).inserting(-1)).contains(f)
                        && IntRange(0, through: n * 2).inserting(-1).contains(i)
                        && IntRange(0, through: n * 2).inserting(1).contains(j)
                        && ZSequences.indices(of: b).inserting(0).contains(k)
                }
                Invariant("Correctness") {
                    !Finished() || ZSequences.rotations(of: b).allSatisfy { other in
                        ZSequences.lexicographicallyPrecedesOrEquals(
                            ZSequences.rotation(of: b, leftBy: k), other.seq)
                            && (ZSequences.rotation(of: b, leftBy: k) != other.seq || k <= other.shift)
                    }
                }
            }
            LeastCircularSubstring
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
