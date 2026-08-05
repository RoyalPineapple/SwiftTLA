import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Majority {
    static var spec: TLASpec {
        TLASpec("Majority") {
            let candidate = Var("candidate", 0)
            let count = Var("count", 0)
            let index = Var("index", 0)
            Variable(candidate, 0)
            Variable(count, 0)
            Variable(index, 0)

            Action("Start") {
                candidate.becomes(1).when(index == 0) &&
                count.becomes(1).when(index == 0) &&
                index.becomes(1).when(index == 0)
            }
            Action("Scan") {
                (index >= 1) && (index < 4) && (candidate == index) && candidate.stays && count.becomes(count + 1) && index.becomes(index + 1) ||
                (index >= 1) && (index < 4) && (candidate != index) && (count > 1) && candidate.stays && count.becomes(count - 1) && index.becomes(index + 1) ||
                (index >= 1) && (index < 4) && (candidate != index) && (count <= 1) && candidate.becomes(index) && count.becomes(1) && index.becomes(index + 1)
            }
        }
    }
}
