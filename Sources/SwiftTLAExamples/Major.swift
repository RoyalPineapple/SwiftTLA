import SwiftTLA
import SwiftTLAGeneration
import SwiftTLAMacros

@TLAModel
public struct Majority {
    var candidate = Var(0)
    var count = Var(0)
    var index = Var(0)
    let N = 4

    func start() {
        candidate.becomes(1).when(index == 0)
        count.becomes(1).when(index == 0)
        index.becomes(1).when(index == 0)
    }

    func scan() {
        (index >= 1) && (index < N) && (candidate == index) && candidate.becomes(candidate) && count.becomes(count + 1) && index.becomes(index + 1) ||
        (index >= 1) && (index < N) && (candidate != index) && (count > 1) && candidate.becomes(candidate) && count.becomes(count - 1) && index.becomes(index + 1) ||
        (index >= 1) && (index < N) && (candidate != index) && (count <= 1) && candidate.becomes(index) && count.becomes(1) && index.becomes(index + 1)
    }
}
