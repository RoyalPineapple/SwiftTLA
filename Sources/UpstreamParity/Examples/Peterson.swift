import SwiftTLA
import SwiftTLAMacros

/// Peterson's two-process mutual-exclusion algorithm from the upstream
/// PlusCal auxiliary-variables collection.
public struct PetersonModel: Sendable {
    public enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1
        case two = 2

        public static var defaultValue: Self { .one }
        public static let finiteValues = allCases
}
