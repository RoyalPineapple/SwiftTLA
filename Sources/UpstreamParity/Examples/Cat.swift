import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/Moving_Cat_Puzzle/Cat.tla and APCat.tla.
@TLAModel
package struct CatModel: Sendable {
    package enum Direction: String, TLAValueType {
        case left
        case right

        package static var defaultValue: Self { .left }
    }

    private enum Step: String, CaseIterable { case Next }

    package static var spec: TLASpec {
        #spec("Cat") { scope in
            Extends(.naturals)
            let Number_Of_Boxes = scope.parameter(as: Int.self, in: 4...6)
            Assume(Number_Of_Boxes >= 2)
            let Boxes = IntRange(1, through: Number_Of_Boxes)
            let Observed_Boxes = IntRange(2, through: Number_Of_Boxes - 1)
            let cat_box = scope.sharedVar(in: Boxes)
            let observed_box = scope.sharedVar(in: Observed_Boxes)
            let direction = scope.sharedVar(in: SetExpr<Direction>.literal(.left, .right))

            Do(Step.Next) {
                With(Boxes) { next in
                    When(next == cat_box + 1 || next == cat_box - 1)
                    Assign(cat_box, to: next)
                }
                let next_box = If(direction == Direction.right,
                    then: observed_box + 1, else: observed_box - 1)
                If(Observed_Boxes.contains(next_box)) {
                    Assign(observed_box, to: next_box)
                } else: {
                    Assign(direction, to: If(direction == Direction.right,
                        then: Direction.left, else: Direction.right))
                }
            }
            // Observe_Box is total and deterministic, so Next projected onto
            // cat_box has exactly the Move_Cat relation used by upstream fairness.
            WeakFairnessNext(on: cat_box)

            let TypeOK = Invariant()
            TypeOK {
                Boxes.contains(cat_box)
                    && Observed_Boxes.contains(observed_box)
                    && SetExpr<Direction>.literal(.left, .right).contains(direction)
            }
            let Victory = Temporal()
            Victory(.eventually(observed_box == cat_box))

            let CatEvenBoxes = Validation { Bind(Number_Of_Boxes, to: 6) }
                .expect(TypeOK, .satisfied).expect(Victory, .satisfied).expectDeadlock(.satisfied)
            CatEvenBoxes
            let CatOddBoxes = Validation { Bind(Number_Of_Boxes, to: 5) }
                .expect(TypeOK, .satisfied).expect(Victory, .satisfied).expectDeadlock(.satisfied)
            CatOddBoxes
            let APCat = Validation { Bind(Number_Of_Boxes, to: 4) }
                .checking(only: [TypeOK]).expect(TypeOK, .satisfied).expectDeadlock(.satisfied)
            APCat
        }
    }
}
