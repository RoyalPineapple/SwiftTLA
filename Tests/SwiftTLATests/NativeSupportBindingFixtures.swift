import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct NativeSupportBindingModel {
    enum Step: String, CaseIterable { case advance, overflow }

    private enum _NativeMachineOperations {
        static func add(_ lhs: Int, _ rhs: Int) throws -> Int { -1 }

        static func mergeUpdate<Value: Equatable & Sendable>(
            _ current: inout Value?, _ incoming: Value?
        ) -> Bool {
            SwiftTLA._NativeMachineOperations.mergeUpdate(&current, incoming)
        }

        static func visitInitialBranch(
            _ visit: () throws -> Void,
            onEvaluationFailure: (NativeMachineEvaluationError) -> Void
        ) throws {
            try SwiftTLA._NativeMachineOperations.visitInitialBranch(
                visit, onEvaluationFailure: onEvaluationFailure)
        }
    }

    static var spec: TLASpec {
        #spec("NativeSupportBindingModel") {
            let algorithm = Algorithm(label: "NativeSupportBindingModel", scoped: { scope in
                let seed = scope.sharedVar(initial: 0)
                let count = scope.sharedVar(initial: seed + 1)
                Do(Step.advance) { Assign(count, to: count + 1) }
                Do(Step.overflow) { Assign(count, to: count + 9_223_372_036_854_775_807) }
            })
            algorithm
        }
    }
}
