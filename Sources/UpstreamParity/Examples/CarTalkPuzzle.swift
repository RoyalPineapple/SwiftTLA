import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct CarTalkPuzzleModel: Sendable {
    package static var spec: TLASpec {
        #spec("CarTalkPuzzle") { scope in
            Extends(.integers, .sequences, .finiteSets, .tlc)
            Import(FunctionsModule.module)
            let N = scope.parameter(as: Int.self, in: Int.all)
            let P = scope.parameter(as: Int.self, in: Int.all)
            let findSolutions = scope.parameter(as: Bool.self)
            let indices = IntRange(1, through: P)
            let weights = IntRange(1, through: N)
            let marker = "$!@$!@$!@$!@$!"
            let breaks = Functions(from: indices, to: weights).filter { pieces in
                Sum(pieces, over: indices) == N && indices.allSatisfy { i in
                    IntRange(i.expr + 1, through: P).allSatisfy { j in pieces[i.expr] <= pieces[j.expr] }
                }
            }
            let pans = Subsets(of: indices)
            let solutions = breaks.filter { pieces in
                weights.allSatisfy { weight in
                    pans.contains { left in
                        pans.contains { right in
                            left.intersection(right).isEmpty
                                && weight.expr + Sum(pieces, over: left) == Sum(pieces, over: right)
                        }
                    }
                }
            }.mapping { pieces in SequenceMapping(length: P) { i in pieces[i.expr] } }
            let threeToTheFourth = 3 * 3 * 3 * 3
            Assume(If(findSolutions, then: PrintT(Pair.literal(marker, solutions)),
                else: PrintT(Pair.literal(marker, Pair<Int, Int>.literal(threeToTheFourth * 3 - 1, 40 + threeToTheFourth)))))
            Validation("Arithmetic") {
                Bind(N, to: 40)
                Bind(P, to: 4)
                Bind(findSolutions, to: false)
            }.checkingDeadlock(false)
            Validation("AllSolutions") {
                Bind(N, to: 15)
                Bind(P, to: 4)
                Bind(findSolutions, to: true)
            }.checkingDeadlock(false)
            Validation("FivePieceSolutions") {
                Bind(N, to: 121)
                Bind(P, to: 5)
                Bind(findSolutions, to: true)
            }.checkingDeadlock(false)
        }
    }
}
