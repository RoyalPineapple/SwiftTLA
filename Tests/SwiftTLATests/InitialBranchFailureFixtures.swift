@testable import SwiftTLA
import SwiftTLAMacros

private extension SwiftTLA.TLAStateProjection.Entry {
    init(token: TLAStateProjection.Token, value: TLAValue) {
        let compiled = try! CompiledRuntime(compilation: InitialFailureOrderModel.spec.compile()).initialOutcomes()
        self = try! compiled.failures[0].formalBindingsBeforeFailure().entries[0]
    }
}

private extension SwiftTLA.InitialEvaluationFailure {
    init(site: Site, failure: NativeMachineEvaluationError,
         projectingBefore: @escaping @Sendable () throws -> TLAStateProjection) {
        let compiled = try! CompiledRuntime(compilation: InitialFailureOrderModel.spec.compile()).initialOutcomes()
        self = compiled.failures[0]
    }
}

private extension Array where Element == SwiftTLA.TLAStateProjection.Token {
    subscript(position: Int) -> Element {
        self.dropFirst(count - 1 - position).first!
    }
}

private extension Optional where Wrapped == Int {
    func map(_ transform: (Int) -> SwiftTLA.InitialEvaluationFailure.Site)
        -> SwiftTLA.InitialEvaluationFailure.Site? { nil }
}

@TLAModel
struct DependentDivisionInitialModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            let algorithm = Algorithm(label: "DependentDivisionInitial", scoped: { scope in
                let divisor = scope.sharedVar(in: SetExpr<Int>.literal(0, 1))
                let quotient = scope.sharedVar(initial: 1 / divisor)
                Do(Step.stay) { Assign(quotient, to: quotient) }
            })
            algorithm
        }
    }
}

@TLAModel
struct SelectedInitialInvariantFailureModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            let Allowed = Invariant()
            let algorithm = Algorithm(label: "SelectedInitialInvariantFailure", scoped: { scope in
                let divisor = scope.sharedVar(in: SetExpr<Int>.literal(0, 1))
                let quotient = scope.sharedVar(initial: 1)
                Do(Step.stay) { Assign(quotient, to: quotient) }
                Allowed { quotient == 1 / divisor }
            })
            algorithm
            InitialStates(satisfying: Allowed)
        }
    }
}

@TLAModel
struct InitialFailureOrderModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            let Allowed = Invariant()
            let algorithm = Algorithm(label: "InitialFailureOrder", scoped: { scope in
                let divisor = scope.sharedVar(in: SetExpr<Int>.literal(0, 1))
                let quotient = scope.sharedVar(initial: 1 / (1 - divisor))
                Do(Step.stay) { Assign(quotient, to: quotient) }
                Allowed { quotient == 1 % (divisor - 1) }
            })
            algorithm
            InitialStates(satisfying: Allowed)
        }
    }
}

@TLAModel
struct DependentFunctionReadInitialModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec {
            let algorithm = Algorithm(label: "DependentFunctionReadInitial", scoped: { scope in
                let table = scope.sharedVar(initial: [0: 42])
                let key = scope.sharedVar(in: SetExpr<Int>.literal(0, 1))
                let result = scope.sharedVar(initial: table[key])
                Do(Step.stay) { Assign(result, to: result) }
            })
            algorithm
        }
    }
}
