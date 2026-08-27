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
            Algorithm("Clock", scoped: { scope in
                let hour = scope.sharedVar("hour", in: 0...23)
                let minute = scope.sharedVar("minute", in: 0...59)
                let second = scope.sharedVar("second", in: 0...59)

                While(Step.tick, true) {
                    Either {
                        When(second < 59)
                        Assign(second, to: second + 1)
                    } or: {
                        Either {
                            When(second == 59)
                            When(minute < 59)
                            Assign(second, to: 0)
                            Assign(minute, to: minute + 1)
                        } or: {
                            Either {
                                When(second == 59)
                                When(minute == 59)
                                When(hour < 23)
                                Assign(second, to: 0)
                                Assign(minute, to: 0)
                                Assign(hour, to: hour + 1)
                            } or: {
                                When(second == 59)
                                When(minute == 59)
                                When(hour == 23)
                                Assign(second, to: 0)
                                Assign(minute, to: 0)
                                Assign(hour, to: 0)
                            }
                        }
                    }
                }

                Invariant("ValidTime") {
                    hour >= 0 && hour <= 23 &&
                    minute >= 0 && minute <= 59 &&
                    second >= 0 && second <= 59
                }
            })
        }
    }
}
