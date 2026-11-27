import Foundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct ClockModel: Sendable {
    private enum Step: String, CaseIterable {
        case tick
    }

    public static var spec: TLASpec {
        #spec("Clock") { scope in
            let hour = scope.sharedVar(initiallyIn: 0...23)
            let minute = scope.sharedVar(initiallyIn: 0...59)
            let second = scope.sharedVar(initiallyIn: 0...59)

            Algorithm("clock", label: "Clock") {
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
            }

            let validTime = Invariant {
                (0...23).contains(hour)
                (0...59).contains(minute)
                (0...59).contains(second)
            }
        }
    }
}
