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

    private enum Step: String, CaseIterable { case next = "Next" }

    package static var spec: TLASpec {
        #spec("Cat") { scope in
            Extends(.naturals)
            let Number_Of_Boxes = scope.parameter(as: Int.self, in: 4...6)
            Assume(Number_Of_Boxes >= 2)
            let Boxes = IntRange(1, through: Number_Of_Boxes)
            let Observed_Boxes = IntRange(2, through: Number_Of_Boxes - 1)
            let cat_box = scope.sharedVar(initiallyIn: Boxes)
            let observed_box = scope.sharedVar(initiallyIn: Observed_Boxes)
            let direction = scope.sharedVar(initiallyIn: SetExpr<Direction>.literal(.left, .right))

            Do(Step.next) {
                With(Boxes) { next in
                    When(next == cat_box + 1 || next == cat_box - 1)
                    cat_box.set(next)
                }
                let next_box = If(direction == Direction.right,
                    then: observed_box + 1, else: observed_box - 1)
                If(Observed_Boxes.contains(next_box)) {
                    observed_box.set(next_box)
                } else: {
                    direction.set(If(direction == Direction.right,
                        then: Direction.left, else: Direction.right))
                }
            }
            // Observe_Box is total and deterministic, so Next projected onto
            // cat_box has exactly the Move_Cat relation used by upstream fairness.
            WeakFairnessNext(on: cat_box)

            let typeOK = Invariant("TypeOK")
            typeOK {
                Boxes.contains(cat_box)
                    && Observed_Boxes.contains(observed_box)
                    && SetExpr<Direction>.literal(.left, .right).contains(direction)
            }
            let Victory = Temporal()
            Victory(.eventually(observed_box == cat_box))

            Validation("CatEvenBoxes") { Bind(Number_Of_Boxes, to: 6) }
                .expect(typeOK, .satisfied).expect(Victory, .satisfied).expectDeadlock(.satisfied)
            Validation("CatOddBoxes") { Bind(Number_Of_Boxes, to: 5) }
                .expect(typeOK, .satisfied).expect(Victory, .satisfied).expectDeadlock(.satisfied)
            Validation("APCat") { Bind(Number_Of_Boxes, to: 4) }
                .checking(only: [typeOK]).expect(typeOK, .satisfied).expectDeadlock(.satisfied)
        }
    }
}
