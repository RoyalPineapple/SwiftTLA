import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct FailingExportModel {
    static var spec: TLASpec {
        #spec("FailingExport") { scope in
            let value = scope.sharedVar("value", in: 0...1)
            SwiftTLA.Action("advance") { value == 1 && value.becomes(2) }
            Invariant("BelowTwo") { value < 2 }
            Invariant("BelowThree") { value < 3 }
            Eventually("ReachesThree", value == 3)
        }
    }
}

@TLAModel
struct CyclicExportModel {
    static var spec: TLASpec {
        #spec("CyclicExport") { scope in
            let value = scope.sharedVar("value", initial: 0)
            SwiftTLA.Action("advance") { value.becomes(1 - value) }
            WeakFairnessNext()
            Eventually("ReachesTwo", value == 2)
        }
    }
}
