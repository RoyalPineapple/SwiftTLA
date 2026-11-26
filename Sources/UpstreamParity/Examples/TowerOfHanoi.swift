// Move one disk at a time until every disk is on the last tower.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/tower_of_hanoi/Hanoi.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TowerOfHanoiModel: Sendable {
    private enum Step: String, CaseIterable { case moveTopDisk = "Next" }

    package static var spec: TLASpec {
        #spec("Hanoi") { scope in
            Import(FunctionsModule.module)
            let diskCount = scope.parameter(tlaName: "D", as: Int.self, in: Set<Int>([3, 5]))
            let pegCount = scope.parameter(tlaName: "N", as: Int.self, in: 3...3)
            let pegs = IntRange(1, through: pegCount)
            let diskRanks = IntRange(1, through: diskCount)
            let diskBits = SequenceMapping(length: diskCount) { rank in
                Fold(SequenceMapping(length: rank - 1) { _ in 2.expr }, startingWith: 1) { factor, total in
                    factor * total
                }
            }
            let allDisksMask = Fold(diskBits, startingWith: 0) { diskBit, total in diskBit + total }
            let towers = scope.sharedVar(initial: SequenceMapping(length: pegCount) { peg in
                If(peg == 1, then: allDisksMask, else: 0)
            })

            Do(Step.moveTopDisk) {
                With(diskRanks, pegs, pegs) { rank, sourcePeg, destinationPeg in
                    let diskBit = diskBits.at(rank)
                    When(sourcePeg != destinationPeg)
                    // Each disk is a single bit. A legal move leaves all smaller bits clear on both pegs.
                    When(towers.at(sourcePeg) % (2 * diskBit) == diskBit && towers.at(destinationPeg) % diskBit == 0)
                    towers.set(SequenceMapping(length: pegCount) { peg in
                        If(peg == sourcePeg, then: towers.at(peg) - diskBit,
                           else: If(peg == destinationPeg, then: towers.at(peg) + diskBit, else: towers.at(peg)))
                    })
                }
            }
            let notSolved = Invariant("NotSolved")
            notSolved { towers.at(pegCount) != allDisksMask }

            Validation("FiveDisks") {
                Bind(diskCount, to: 5)
                Bind(pegCount, to: 3)
            }.expect(notSolved, .violated)
        }
    }
}
