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
        #spec { scope in
            let three = scope.sharedVar(initial: 0)
            let five = scope.sharedVar(initial: 0)
            let Capacity = Invariant()

            Do(Step.fillThree, when: three < 3) {
                three.set(3)
            }
            Do(Step.fillFive, when: five < 5) {
                five.set(5)
            }
            Do(Step.emptyThree, when: three > 0) {
                three.set(0)
            }
            Do(Step.emptyFive, when: five > 0) {
                five.set(0)
            }
            Do(Step.pourThreeIntoFive, when: three > 0 && five < 5) {
                If(three + five <= 5) {
                    five += three
                    three.set(0)
                } else: {
                    let amount = 5 - five
                    three.set(three - amount)
                    five.set(5)
                }
            }
            Do(Step.pourFiveIntoThree, when: five > 0 && three < 3) {
                If(three + five <= 3) {
                    three += five
                    five.set(0)
                } else: {
                    let amount = 3 - three
                    five.set(five - amount)
                    three.set(3)
                }
            }
            Capacity { three >= 0 && three <= 3 && five >= 0 && five <= 5 }
        }
    }
}
