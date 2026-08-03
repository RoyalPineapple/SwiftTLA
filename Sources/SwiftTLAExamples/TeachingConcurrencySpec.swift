import SwiftTLA

public enum TeachingConcurrencySpec {
    public static let N = 2
    public static let x = Var<TLASet>("x")
    public static let y = Var<TLASet>("y")

    public static let processValues: [TLAValue] = (0..<N).map { .int($0) }
    public static let zeroFunction = TLAValue.set(Set(processValues.map { k in
        .record([String(describing: k): .int(0)])
    }))

    public static let spec = TLASpec("Simple") {
        Variable(x, zeroFunction)
        Variable(y, zeroFunction)

        for i in 0..<N {
            let previous = (i - 1 + N) % N
            Act("a\(i)") {
                functionApply(x, .int(i)) == 0
                && (next(x) == except(x, at: .int(i), value: .int(1)))
                && (next(y) == y)
            }
            Act("b\(i)") {
                functionApply(x, .int(i)) == 1
                && (next(y) == except(y, at: .int(i), value: functionApply(x, .int(previous))))
                && (next(x) == x)
            }
        }

        Inv("SomeYisOne") {
            exists(.setLiteral(processValues), functionApply(y, .variable("_q")) == .int(1))
        }
    }
}
