import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct HourClock2Model: Sendable {
    public enum Step: String, CaseIterable {
        case HCnxt2
    }

    public enum ClockProcess: String, CaseIterable {
        case clock

}
