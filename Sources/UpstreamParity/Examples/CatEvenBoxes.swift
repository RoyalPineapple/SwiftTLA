import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct CatEvenBoxesModel: Sendable {
    package enum Direction: String, TLAValueType {
        case left
        case right

        package static var defaultValue: Self { .left }
    }

    package static var spec: TLASpec {
        #spec("Cat") { scope in
            Extends(.naturals)
            let catBox = scope.sharedVar("catBox", in: 1...6)
            let observedBox = scope.sharedVar("observedBox", in: 2...5)
            let direction = scope.sharedVar("direction", in: SetExpr<Direction>.literal(.left, .right))

            Invariant("TypeOK") {
                catBox >= 1 && catBox <= 6
                    && observedBox >= 2 && observedBox <= 5
                    && (direction == Direction.left || direction == Direction.right)
            }

            SwiftTLA.Action("Next") {
                ((catBox < 6 && catBox.becomes(catBox + 1)) || (catBox > 1 && catBox.becomes(catBox - 1)))
                    && ((direction == Direction.right && observedBox < 5 && observedBox.becomes(observedBox + 1))
                        || (direction == Direction.right && observedBox == 5 && direction.becomes(Direction.left))
                        || (direction == Direction.left && observedBox > 2 && observedBox.becomes(observedBox - 1))
                        || (direction == Direction.left && observedBox == 2 && direction.becomes(Direction.right)))
            }
        }
    }
}

@TLAModel
package struct CatOddBoxesModel: Sendable {
    package enum Direction: String, TLAValueType {
        case left
        case right

        package static var defaultValue: Self { .left }
    }

    package static var spec: TLASpec {
        #spec("Cat") { scope in
            Extends(.naturals)
            let catBox = scope.sharedVar("catBox", in: 1...5)
            let observedBox = scope.sharedVar("observedBox", in: 2...4)
            let direction = scope.sharedVar("direction", in: SetExpr<Direction>.literal(.left, .right))

            Invariant("TypeOK") {
                catBox >= 1 && catBox <= 5
                    && observedBox >= 2 && observedBox <= 4
                    && (direction == Direction.left || direction == Direction.right)
            }

            SwiftTLA.Action("Next") {
                ((catBox < 5 && catBox.becomes(catBox + 1)) || (catBox > 1 && catBox.becomes(catBox - 1)))
                    && ((direction == Direction.right && observedBox < 4 && observedBox.becomes(observedBox + 1))
                        || (direction == Direction.right && observedBox == 4 && direction.becomes(Direction.left))
                        || (direction == Direction.left && observedBox > 2 && observedBox.becomes(observedBox - 1))
                        || (direction == Direction.left && observedBox == 2 && direction.becomes(Direction.right)))
            }
        }
    }
}

extension Example {
    package static let catEvenBoxes = Entry(
        id: "Moving_Cat_Puzzle/CatEvenBoxes",
        upstreamSpec: "Moving_Cat_Puzzle",
        upstreamModule: "specifications/Moving_Cat_Puzzle/Cat.tla",
        upstreamCfg: "specifications/Moving_Cat_Puzzle/CatEvenBoxes.cfg",
        expectedDistinct: 48,
        spec: CatEvenBoxesModel.spec,
        notes: "Number_Of_Boxes=6. Typed direction phase. TLC upstream = 48."
    )
}
