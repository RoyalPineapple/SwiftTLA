import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConfiguredFunctionDomainModel {
    enum Step: String, CaseIterable { case keep }

    static var spec: TLASpec {
        #spec("ConfiguredFunctionDomainModel") { scope in
            let size = scope.parameter(as: Int.self, in: 0...2)
            let total = Invariant()
            Algorithm("Worker", scoped: { algorithm in
                let values = algorithm.sharedVar(in: Functions(
                    from: IntRange(0, through: size - 1), to: Set<Int>([0, 1])))
                Do(Step.keep) { Assign(values, to: values) }
                total { Functions(from: IntRange(0, through: size - 1), to: Set<Int>([0, 1])).contains(values) }
            })
            Validation("Empty") { Bind(size, to: 0) }
            Validation("Two keys") { Bind(size, to: 2) }
        }
    }
}

@TLAModel
struct ConfiguredFunctionMappingModel {
    enum Step: String, CaseIterable { case keep }

    static var spec: TLASpec {
        #spec("ConfiguredFunctionMappingModel") { scope in
            let size = scope.parameter(as: Int.self, in: 0...2)
            Algorithm("Worker", scoped: { algorithm in
                let values = algorithm.sharedVar(initial: Dictionary<Int, Int>.mapping(
                    over: IntRange(0, through: size - 1)) { key in key + size })
                let constants = algorithm.sharedVar(initial: Dictionary<Int, Int>.mapping(
                    over: IntRange(0, through: size - 1)) { _ in -1 })
                Do(Step.keep) {
                    Assign(values, to: values)
                    Assign(constants, to: constants)
                }
            })
            Validation("Empty") { Bind(size, to: 0) }
            Validation("Two keys") { Bind(size, to: 2) }
        }
    }
}

enum CollidingFunctionKey: Hashable, TLAValueType {
    case first, second
    static var defaultValue: Self { .first }
    var tlaValue: TLAValue { .int(0) }
    init?(formalValue: TLAValue) {
        guard formalValue == .int(0) else { return nil }
        self = .first
    }
}

// Independent formal actions exercise generated failures without advancing process control.
@TLAModel
struct FunctionSpaceMembershipModel {
    enum Key: String, CaseIterable, FiniteTLAValueDomain { case first, second, third }

    static var spec: TLASpec {
        TLASpec("FunctionSpaceMembershipModel") {
            let result = Var<Bool>("result")
            let zero = Var<Int>("zero")
            Variable(result, false)
            Variable(zero, 0)
            SwiftTLA.Action("accepted") {
                result.becomes(Functions(from: Key.all, to: SetExpr<Int>.literal(0, 1))
                    .contains(Function<Key, Int>.mapping { _ in 0 }))
            }
            SwiftTLA.Action("candidateFailure") {
                result.becomes(Functions(from: Key.all, to: SetExpr<Int>())
                    .contains(Function<Key, Int>.mapping { _ in 1 / zero.expr }))
            }
        }
    }
}
