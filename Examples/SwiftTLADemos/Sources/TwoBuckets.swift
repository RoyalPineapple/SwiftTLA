import SwiftTLA
import SwiftTLAMacros

/// The Die Hard water-jug puzzle, expressed as a generated formal machine.
///
/// Each operation has one singleton process. This preserves the formal model's
/// independent scheduling while exposing a clean Swift action surface such as
/// `try machine.send(.fillThree)`.
@TLAModel
public struct TwoBuckets {
    private enum FillThreeProcess: String, CaseIterable {
        case fillThree

        }
    }

}
