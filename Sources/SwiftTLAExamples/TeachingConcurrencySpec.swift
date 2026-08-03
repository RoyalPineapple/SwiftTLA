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
                let write: ActionExpr = functionApply(x, StateExpr.int(i)) == StateExpr.int(0)
                    && (next(x) == except(x, at: StateExpr.int(i), value: StateExpr.int(1)))
                    && (next(y) == y)
                write
            }
            Act("b\(i)") {
                let write: ActionExpr = functionApply(x, StateExpr.int(i)) == StateExpr.int(1)
                    && (next(y) == except(y, at: StateExpr.int(i), value: functionApply(x, StateExpr.int(previous))))
                    && (next(x) == x)
                write
            }
        }

        Inv("SomeYisOne") {
            exists(.setLiteral(processValues.map { .value($0) }), functionApply(y, StateExpr.variable("_q")) == StateExpr.int(1))
        }
    }
}
