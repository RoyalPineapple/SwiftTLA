import SwiftTLA
import SwiftTLAMacros

private extension SwiftTLA.TLAValue {
    static func int(_ value: Swift.Int) -> Self { .string("caller-int") }
}

private extension SwiftTLA._NativeMachineOperations {
    static func visitInitialBranch(
        _ visit: () throws -> Void,
        onEvaluationFailure: (NativeMachineEvaluationError) -> Void
    ) throws {}

    static func add(_ lhs: Swift.Int, _ rhs: Swift.Int) throws -> Swift.Int { -2 }
}

private func emptyInitialOutcomes<State: Sendable>() -> InitialEvaluationOutcomes<State> {
    .init(states: [], failures: [])
}

private extension InitialEvaluationOutcomes where State == NativeSupportBindingModel.Snapshot {
    var states: [State] { [] }

    init(states: [State], failures: [InitialEvaluationFailure]) {
        self = emptyInitialOutcomes()
    }
}

private extension NativeSupportBindingModel {
    static func _initialStates(_selectedInitial: State?) throws -> (
        states: [Snapshot], failures: [InitialEvaluationFailure], firstFailure: NativeMachineEvaluationError?
    ) { ([], [], nil) }

    static func _initialStates() throws -> InitialEvaluationOutcomes<Snapshot> {
        .init(states: [], failures: [])
    }

    static func _completedInitialStates() throws -> [Snapshot] { [] }

    static func _completedInitialStates(_selectedInitial: State?) throws -> [State] { [] }
}

private extension ArraySlice where Element == NativeSupportBindingModel.Snapshot {
    mutating func popFirst() -> Element? { nil }
}

private func || (lhs: Bool, rhs: @autoclosure () -> Bool) -> Bool { false }

private extension Array where Element == NativeSupportBindingModel.Snapshot {
    func map<Result>(_ transform: (Element) throws -> Result) rethrows -> [Result] { [] }

    mutating func append(_ element: Element) {}
}

private extension Array {
    mutating func append(_ element: Element) {
        guard !(element is NativeSupportBindingModel.Snapshot) else { return }
        self += [element]
    }
}

private extension Array where Element: Sendable {
    mutating func append(_ element: Element) {
        guard !(element is NativeSupportBindingModel.Snapshot) else { return }
        self += [element]
    }
}

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
