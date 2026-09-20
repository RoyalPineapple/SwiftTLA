import SwiftTLA
import SwiftTLAMacros

/// The water-jug puzzle with six independently enabled atomic moves.
@TLAModel
public struct TwoBuckets: Sendable {
    private enum Step: String, CaseIterable {
        case fillThree, fillFive, emptyThree, emptyFive
        case pourThreeIntoFive, pourFiveIntoThree
    }

    public static var spec: TLASpec {
        #spec("TwoBuckets") { scope in
            let three = scope.sharedVar(initial: 0)
            let five = scope.sharedVar(initial: 0)
            let Capacity = Invariant()

            Do(Step.fillThree) {
                When(three < 3)
                Assign(three, to: 3)
            }
            Do(Step.fillFive) {
                When(five < 5)
                Assign(five, to: 5)
            }
            Do(Step.emptyThree) {
                When(three > 0)
                Assign(three, to: 0)
            }
            Do(Step.emptyFive) {
                When(five > 0)
                Assign(five, to: 0)
            }
            Do(Step.pourThreeIntoFive) {
                When(three > 0 && five < 5)
                If(three + five <= 5) {
                    Assign(five, to: five + three)
                    Assign(three, to: 0)
                } else: {
                    let amount = 5 - five
                    Assign(three, to: three - amount)
                    Assign(five, to: 5)
                }
            }
            Do(Step.pourFiveIntoThree) {
                When(five > 0 && three < 3)
                If(three + five <= 3) {
                    Assign(three, to: three + five)
                    Assign(five, to: 0)
                } else: {
                    let amount = 3 - three
                    Assign(five, to: five - amount)
                    Assign(three, to: 3)
                }
            }
            Capacity { three >= 0 && three <= 3 && five >= 0 && five <= 5 }
        }
    }
}
