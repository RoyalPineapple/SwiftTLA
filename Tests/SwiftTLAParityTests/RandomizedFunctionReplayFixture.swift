import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RandomizedFunctionReplay {
    enum Color: String, TLAValueType {
        case white, black
        static var defaultValue: Self { .white }
    }

    struct Token: Hashable, Sendable {
        let pos: Int
        let color: Color
    }

    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("RandomizedFunctionReplay") { scope in
            Extends(.randomization)
            let samples = scope.sharedVar(in: RandomSubset(upTo: 1,
                from: Functions(from: IntRange(1, through: 2), to: SetExpr<Bool>.literal(false, true))))
            let mapping = scope.sharedVar(in: RandomSubset(upTo: 1,
                from: Functions(from: SetExpr<Int>.literal(0, 2), to: SetExpr<Bool>.literal(false, true))))
            let token = scope.sharedVar(initial: Token.expression(pos: 0, color: Color.white))
            Do(Step.stay) {
                Assign(samples, to: samples)
                Assign(mapping, to: mapping)
                Assign(token, to: token)
            }
        }
    }
}
