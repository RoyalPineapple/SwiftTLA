import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct ClockModel: Sendable {
    private enum Step: String, CaseIterable {
        case tick
    }

    public static var spec: TLASpec {
        #spec("Clock") {
            let ValidTime = Invariant()
            let clock = Algorithm(label: "Clock") { scope in
                let hour = scope.sharedVar(initiallyIn: 0...23)
                let minute = scope.sharedVar(initiallyIn: 0...59)
                let second = scope.sharedVar(initiallyIn: 0...59)

                Loop(Step.tick) {
                    Either {
                        When(second < 59) {
                            second += 1
                        }
                        When(second == 59, minute < 59) {
                            second.set(0)
                            minute += 1
                        }
                        When(second == 59, minute == 59, hour < 23) {
                            second.set(0)
                            minute.set(0)
                            hour += 1
                        }
                        When(second == 59, minute == 59, hour == 23) {
                            second.set(0)
                            minute.set(0)
                            hour.set(0)
                        }
                    }
                }

                ValidTime {
                    hour >= 0 && hour <= 23 &&
                    minute >= 0 && minute <= 59 &&
                    second >= 0 && second <= 59
                }
            }
            clock
        }
    }
}
