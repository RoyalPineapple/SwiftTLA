// Slide one piece one square at a time until the large square reaches the exit.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SlidingPuzzles/SlidingPuzzles.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SlidingPuzzlesModel: Sendable {
    package typealias Position = Pair<Int, Int>
    package typealias Piece = Set<Position>
    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("SlidingPuzzles") { scope in
            let positions = IntRange(0, through: 3).flatMapping { x in
                IntRange(0, through: 4).mapping { y in Pair<Int, Int>.literal(x, y) }
            }
            let directions = Set<Position>([Pair(first: 1, second: 0), Pair(first: 0, second: 1),
                                            Pair(first: -1, second: 0), Pair(first: 0, second: -1)])
            let board = scope.sharedVar(initial: Set<Piece>([
                [Pair(first: 0, second: 0), Pair(first: 0, second: 1)],
                [Pair(first: 1, second: 0), Pair(first: 2, second: 0), Pair(first: 1, second: 1), Pair(first: 2, second: 1)],
                [Pair(first: 3, second: 0), Pair(first: 3, second: 1)],
                [Pair(first: 0, second: 2), Pair(first: 0, second: 3)],
                [Pair(first: 1, second: 2), Pair(first: 2, second: 2)],
                [Pair(first: 3, second: 2), Pair(first: 3, second: 3)],
                [Pair(first: 1, second: 3)],
                [Pair(first: 2, second: 3)],
                [Pair(first: 0, second: 4)],
                [Pair(first: 3, second: 4)]
            ]))
            let empty = positions.subtracting(board.flatMapping { piece in piece })
            Do(Step.next) {
                With(empty, directions) { space, direction in
                    let neighbor = Pair<Int, Int>.literal(space.first() + direction.first(), space.second() + direction.second())
                    When(positions.contains(neighbor) && !empty.contains(neighbor))
                    let piece = Select(from: board) { candidate in
                        candidate.contains(neighbor) && board.allSatisfy { other in !other.contains(neighbor) || other == candidate }
                    }
                    let shifted = piece.mapping { point in
                        Pair<Int, Int>.literal(point.first() - direction.first(), point.second() - direction.second())
                    }
                    let others = board.removing(piece)
                    When(shifted.isSubset(of: positions) && others.allSatisfy { other in shifted.intersection(other).isEmpty })
                    board.set(others.inserting(shifted))
                }
            }
            Invariant("TypeOK") { board.allSatisfy { piece in piece.isSubset(of: positions) } }
            let exit = positions.filter { square in
                square.first() >= 1 && square.first() <= 2 && square.second() >= 3
            }
            let goal = Invariant("KlotskiGoal")
            goal { !board.contains(exit) }
            Validation("Upstream") {}.behavior(.initialAndNext).expect(goal, .violated)
        }
    }
}
