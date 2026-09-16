import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct First {
    static var spec: TLASpec {
        #spec("First") { scope in
            let count = scope.sharedVar(_name: "count", initial: 0)
            Invariant("Safe") { count == 0 }
        }
    }
}

@TLAModel
struct Second {
    static var spec: TLASpec {
        #spec("Second") { scope in
            let count = scope.sharedVar(_name: "count", initial: 0)
            Invariant("Safe") { count == 0 }
        }
    }
}

let foreignProperty: First.Property = Second.Property.Safe
let stringProperty: First.Property = "Safe"
let missingProperty: First.Property = .Missing

let unary = Eventually()
let binary = LeadsTo()
let excessArguments = unary(true, false)
let missingArgument = binary(true)
let wrongPredicate = unary(1)
let undefinedProperty = TLASpec("Undefined") { unary }

let goal = Reachable()
let wrongReachabilityPredicate = goal { 1 }
let undefinedReachability = TLASpec("Undefined") { goal }

let invalidLabels = #spec("InvalidLabels") {
    let empty = Invariant(label: "")
    let interpolated = Reachable(label: "Goal \(1)")
    empty { true }
    interpolated { true }
}

let invalidRefinementLabels = #spec("InvalidRefinementLabels") {
    let target = Instance("Target", of: TLASpec("Abstract") {})
    target
    let empty = Refinement(instance: target, mappings: [], label: "")
    let interpolated = Refinement(instance: target, mappings: [], label: "Claim \(1)")
    empty
    interpolated
}
