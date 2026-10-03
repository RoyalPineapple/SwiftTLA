import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConfiguredFunctionDomainModel {
    enum Step: String, CaseIterable { case keep }

    static var spec: TLASpec {
        #spec("ConfiguredFunctionDomainModel") { scope in
            let size = scope.parameter(as: Int.self, in: 0...2)
            let total = Invariant()
            let worker = Algorithm(label: "Worker", scoped: { algorithm in
                let values = algorithm.sharedVar(in: Functions(
                    from: IntRange(0, through: size - 1), to: Set<Int>([0, 1])))
                Do(Step.keep) { Assign(values, to: values) }
                total { Functions(from: IntRange(0, through: size - 1), to: Set<Int>([0, 1])).contains(values) }
            })
            worker
            let empty = Validation(label: "Empty") { Bind(size, to: 0) }
            empty
            let twoKeys = Validation(label: "Two keys") { Bind(size, to: 2) }
            twoKeys
        }
    }
}

@TLAModel
struct ConfiguredFunctionMappingModel {
    enum Step: String, CaseIterable { case keep }

    static var spec: TLASpec {
        #spec("ConfiguredFunctionMappingModel") { scope in
            let size = scope.parameter(as: Int.self, in: 0...2)
            let worker = Algorithm(label: "Worker", scoped: { algorithm in
                let values = algorithm.sharedVar(initial: Dictionary<Int, Int>.mapping(
                    over: IntRange(0, through: size - 1)) { key in key + size })
                let constants = algorithm.sharedVar(initial: Dictionary<Int, Int>.mapping(
                    over: IntRange(0, through: size - 1)) { _ in -1 })
                Do(Step.keep) {
                    Assign(values, to: values)
                    Assign(constants, to: constants)
                }
            })
            worker
            let empty = Validation(label: "Empty") { Bind(size, to: 0) }
            empty
            let twoKeys = Validation(label: "Two keys") { Bind(size, to: 2) }
            twoKeys
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

@TLAModel
struct FunctionSpaceMembershipModel {
    enum Key: String, CaseIterable, FiniteTLAValueDomain { case first, second, third }
    enum Step: String, CaseIterable { case accepted, candidateFailure, largeAccepted }

    static var spec: TLASpec {
        #spec { scope in
            let result = scope.sharedVar(initial: false)
            let zero = scope.sharedVar(initial: 0)
            Do(Step.accepted) {
                Assign(result, to: Functions(from: Key.all, to: Set<Int>([0, 1]))
                    .contains(Function<Key, Int>.mapping { _ in 0 }))
            }
            Do(Step.candidateFailure) {
                Assign(result, to: Functions(from: Key.all, to: Set<Int>([]))
                    .contains(Function<Key, Int>.mapping { _ in 1 / zero }))
            }
            Do(Step.largeAccepted) {
                Assign(result, to: Functions(from: IntRange(0, through: 99), to: Set<Int>([0, 1]))
                    .contains(Dictionary<Int, Int>.mapping(over: IntRange(0, through: 99)) { _ in 0 }))
            }
        }
    }
}
