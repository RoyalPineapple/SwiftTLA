import SwiftTLA

public enum MajorSpec {
    public static let candidate = Var<Int>("candidate")
    public static let count = Var<Int>("count")
    public static let index = Var<Int>("index")
    public static let N = 4
    public static let spec = TLASpec("Majority") {
        Variable(candidate, 0); Variable(count, 0); Variable(index, 0)
        Action("Start") { (index == 0) && (candidate.next == 1) && (count.next == 1) && (index.next == 1) }
        Action("Vote") {
            let same: ActionExpr = (index >= 1) && (index < N) && (candidate == index) && (candidate.next == candidate) && (count.next == count + 1) && (index.next == index + 1)
            let keep: ActionExpr = (index >= 1) && (index < N) && (candidate != index) && (count > 1) && (candidate.next == candidate) && (count.next == count - 1) && (index.next == index + 1)
            let swap: ActionExpr = (index >= 1) && (index < N) && (candidate != index) && (count <= 1) && (candidate.next == index) && (count.next == 1) && (index.next == index + 1)
            same || keep || swap
        }
    }
}
