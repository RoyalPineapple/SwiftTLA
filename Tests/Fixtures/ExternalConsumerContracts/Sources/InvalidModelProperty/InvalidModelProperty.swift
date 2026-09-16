import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct First {
    static var spec: TLASpec {
        #spec("First") { scope in
            let count = scope.sharedVar("count", initial: 0)
            Invariant("Safe") { count == 0 }
        }
    }
}

@TLAModel
struct Second {
    static var spec: TLASpec {
        #spec("Second") { scope in
            let count = scope.sharedVar("count", initial: 0)
            Invariant("Safe") { count == 0 }
        }
    }
}

let foreignProperty: First.Property = Second.Property.Safe
let stringProperty: First.Property = "Safe"
let missingProperty: First.Property = .Missing
