import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct TypedParameterSelection {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec { scope in
            let result = scope.sharedVar(initial: 0)
            Do(Step.choose, over: Set<Int>([1, 2])) { selection in
                Assign(result, to: selection + 1)
            }
        }
    }
}

@TLAModel
struct CollectionParameterUpdates {
    enum Key: String, CaseIterable, FiniteTLAValueDomain {
        case first, second
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
    }
    enum Step: String, CaseIterable { case replace }

    static var spec: TLASpec {
        #spec { scope in
            let table = scope.sharedVar(initial: Function<Key, Int>.literal((.first, 0), (.second, 0)))
            let partial = scope.sharedVar(initial: PartialFunction<Key, Int>.empty)
            let sequence = scope.sharedVar(initial: ZeroBasedSequence<Int>.literal(0, 0))
            Do(Step.replace, over: Key.all, Set<Int>([1, 2])) { key, value in
                Assign(table, to: table.updating(key, to: value))
                Assign(partial, to: partial.overriding(key, with: value))
                Assign(sequence, to: sequence.updating(0, to: value))
            }
        }
    }
}
