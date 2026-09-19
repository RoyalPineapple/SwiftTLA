import SwiftTLA
import SwiftTLAMacros

enum ByteExactProjectionCase: String, TLAValueType, Sendable {
    case composed = "\u{e9}"
    static var defaultValue: Self { .composed }
}

@_TLARecordValue
struct LossyMemberProjectionRecord: Sendable {
    let member: CollidingSetMember
}
