// A loop scans a sequence while keeping the largest value seen so far.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/LearnProofs/FindHighest.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct FindHighestModel: Sendable {
    private enum Step: String, CaseIterable {
        case lb
    }

    package static var spec: TLASpec {
        #spec("Highest") { model in
            Extends(.integers)
            let MaxLength = model.parameter(as: Int.self, in: 3...3)
            let MaxNat = model.parameter(as: Int.self, in: 4...4)
            let Highest = Algorithm { scope in
                let f = scope.sharedVar(initiallyIn: Sequences(
                    of: IntRange(0, through: MaxNat),
                    lengths: IntRange(0, through: MaxNat)
                ))
                let h = scope.sharedVar(initial: -1)
                let i = scope.sharedVar(initial: 1)

                While(Step.lb, i <= f.count) {
                    h.set(If(h >= f[i], then: h, else: f[i]))
                    i += 1
                }

                StateConstraint(f.count <= MaxLength)
                Invariant("TypeOK") {
                    f.count <= MaxNat
                    IntRange(1, through: f.count).allSatisfy { index in
                        f[index] >= 0 && f[index] <= MaxNat
                    }
                    i >= 1 && i <= f.count + 1 && i <= MaxNat
                    h >= -1 && h <= MaxNat
                }
                Invariant("InductiveInvariant") {
                    IntRange(1, through: i - 1).allSatisfy { index in
                        f[index] <= h
                    }
                }
                Invariant("DoneIndexValue") {
                    (!Finished()) || i == f.count + 1
                }
                Invariant("Correctness") {
                    (!Finished()) || IntRange(1, through: f.count).allSatisfy { index in
                        f[index] <= h
                    }
                }
            }
            Highest
            Validation("MCFindHighest") {
                Bind(MaxLength, to: 3)
                Bind(MaxNat, to: 4)
            }
        }
    }
}
