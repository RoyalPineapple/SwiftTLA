import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Majority {
    static var spec: TLASpec {
        TLASpec("Majority") {
            let candidate = Var(0)
            let count = Var(0)
            let index = Var(0)
            Action("start") {
                candidate.becomes(1).when(index == 0) &&
                count.becomes(1).when(index == 0) &&
                index.becomes(1).when(index == 0)
            }
            Action("scan") {
                (index >= 1) && (index < 4) && (candidate == index) && candidate.stays && count.becomes(count + 1) && index.becomes(index + 1) ||
                (index >= 1) && (index < 4) && (candidate != index) && (count > 1) && candidate.stays && count.becomes(count - 1) && index.becomes(index + 1) ||
                (index >= 1) && (index < 4) && (candidate != index) && (count <= 1) && candidate.becomes(index) && count.becomes(1) && index.becomes(index + 1)
            }
        }
    }
}
