import SwiftTLA
import SwiftTLAMacros

/// The bounded `Boulanger` process-control model from the upstream PlusCal
/// corpus. The bound and state constraint match MCBoulanger.
@TLAModel
public struct BoulangerModel: Sendable {
    public static let corpusEntry = CanonicalCorpusEntry(
        id: "boulanger-upstream-port",
        specification: { BoulangerModel.spec },
        swiftConfiguration: .init(checks: [.init("StateConstraint", kind: .constraint)]),
        plusCalConfiguration: .init(checks: [.init("StateConstraint", kind: .constraint)])
    )

    public enum Process: Int, CaseIterable {
        case one = 1
        case two = 2

        }
    }
}
