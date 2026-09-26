import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ReachabilityExportModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("ReachabilityExport") { scope in
            let value = scope.sharedVar(_name: "value", initial: 0)
            Algorithm("Counter") {
                Do(Step.advance, when: value < 2) {
                    Assign(value, to: value + 1)
                    Goto(Step.advance)
                }
            }
            Reachable("Positive") { value > 0 }
            Reachable("BeyondLimit") { value > 2 }
        }
    }
}

@TLAModel
struct FailingExportModel {
    static var spec: TLASpec {
        #spec("FailingExport") { scope in
            let value = scope.sharedVar(_name: "value", in: 0...1)
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
            let value = scope.sharedVar(_name: "value", initial: 0)
            SwiftTLA.Action("advance") { value.becomes(1 - value) }
            WeakFairnessNext()
            Eventually("ReachesTwo", value == 2)
        }
    }
}

struct CollidingExportSnapshot: Hashable, Sendable {
    let value: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}
