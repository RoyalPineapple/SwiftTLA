@_spi(Internal) import SwiftTLA

public enum MajorSpec {
    public static let candidate = Var<Int>("candidate")
    public static let count = Var<Int>("count")
    public static let index = Var<Int>("index")
    public static let N = 4
    public static let spec = TLASpec("Majority") {
        Variable(candidate, 0); Variable(count, 0); Variable(index, 0)
        Action("Start") { (index == 0) && (candidate.prime == 1) && (count.prime == 1) && (index.prime == 1) }
        Action("Vote") {
            let same: ActionExpr = (index >= 1) && (index < N) && (candidate == index) && (candidate.prime == candidate) && (count.prime == count + 1) && (index.prime == index + 1)
            let keep: ActionExpr = (index >= 1) && (index < N) && (candidate != index) && (count > 1) && (candidate.prime == candidate) && (count.prime == count - 1) && (index.prime == index + 1)
            let swap: ActionExpr = (index >= 1) && (index < N) && (candidate != index) && (count <= 1) && (candidate.prime == index) && (count.prime == 1) && (index.prime == index + 1)
            same || keep || swap
        }
    }
}
