// Move one disk at a time until every disk is on the last tower.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/tower_of_hanoi/Hanoi.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TowerOfHanoiModel: Sendable {
    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("Hanoi") { scope in
            Import(FunctionsModule.module)
            let D = scope.parameter(as: Int.self, in: Set<Int>([3, 5]))
            let N = scope.parameter(as: Int.self, in: 3...3)
            let pegs = IntRange(1, through: N)
            let ranks = IntRange(1, through: D)
            let disks = SequenceMapping(length: D) { rank in
                Fold(SequenceMapping(length: rank - 1) { _ in 2.expr }, startingWith: 1) { factor, total in
                    factor * total
                }
            }
            let fullTower = Fold(disks, startingWith: 0) { disk, total in disk + total }
            let towers = scope.sharedVar(initial: SequenceMapping(length: N) { peg in
                If(peg == 1, then: fullTower, else: 0)
            })

            Do(Step.next) {
                With(ranks, pegs, pegs) { rank, from, to in
                    let disk = disks.at(rank)
                    When(from != to)
                    // Each disk is a single bit. A legal move leaves all smaller bits clear on both pegs.
                    When(towers.at(from) % (2 * disk) == disk && towers.at(to) % disk == 0)
                    towers.set(SequenceMapping(length: N) { peg in
                        If(peg == from, then: towers.at(peg) - disk,
                           else: If(peg == to, then: towers.at(peg) + disk, else: towers.at(peg)))
                    })
                }
            }
            let goal = Invariant("NotSolved")
            goal { towers.at(N) != fullTower }

            Validation("FiveDisks") {
                Bind(D, to: 5)
                Bind(N, to: 3)
            }.expect(goal, .violated)
        }
    }
}
