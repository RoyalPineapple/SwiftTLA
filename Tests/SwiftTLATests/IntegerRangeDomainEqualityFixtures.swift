import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct IntegerRangeDomainEqualityModel: Sendable {
    enum Step: String, CaseIterable {
        case check, reversed, large, domainFirstFailure, rangeFirstFailure
    }

    static var spec: TLASpec {
        #spec("IntegerRangeDomainEqualityModel") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>(), Set<Int>([1, 2]), Set<Int>([1, 3])]))
            let lower = scope.parameter(as: Int.self, in: -1...3)
            let upper = scope.parameter(as: Int.self, in: 0...3)
            let values = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: members) { _ in 0 })
            let result = scope.sharedVar(initial: false)
            let zero = scope.sharedVar(initial: 0)
            let invalidDomain = Dictionary<Int, Int>.mapping(over: IntRange(0, through: 1 / zero)) { _ in 0 }.keys

            Do(Step.check) {
                Assign(result, to: values.keys == IntRange(lower, through: upper))
            }
            Do(Step.reversed) {
                Assign(result, to: IntRange(lower, through: upper) == values.keys)
            }
            Do(Step.large) {
                Assign(result, to: values.keys == IntRange(0, through: 1_000_000_000))
            }
            Do(Step.domainFirstFailure) {
                Assign(result, to: invalidDomain == IntRange(0, through: 9_223_372_036_854_775_807))
            }
            Do(Step.rangeFirstFailure) {
                Assign(result, to: IntRange(0, through: 9_223_372_036_854_775_807) == invalidDomain)
            }
        }
    }
}
