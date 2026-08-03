import SwiftTLA

public enum MajorSpec {
    public static let candidate = Var<Int>("candidate")
    public static let count = Var<Int>("count")
    public static let index = Var<Int>("index")
    public static let N = 5

    public static let spec = TLASpec("Major") {
        Variable(candidate, 0)
        Variable(count, 0)
        Variable(index, 0)
        Act("Start") { (index == 0) && (next(candidate) == 1) && (next(count) == 1) && (next(index) == 1) }
        Act("Vote") {
            (index >= 1) && (index < N)
            && (((candidate == index) && (next(candidate) == candidate) && (next(count) == count + 1) && (next(index) == index + 1))
            || ((candidate != index) && (count > 1) && (next(candidate) == candidate) && (next(count) == count - 1) && (next(index) == index + 1))
            || ((candidate != index) && (count <= 1) && (next(candidate) == index) && (next(count) == 1) && (next(index) == index + 1)))
        }
    }
    public static let expectedStates = 0
}
