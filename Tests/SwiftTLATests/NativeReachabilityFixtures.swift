import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct BranchingControl {
    enum Step: String, CaseIterable { case enter, choose }
    static var spec: TLASpec {
        #spec("BranchingControl") {
            Algorithm("BranchingControl", scoped: { scope in
                let value = scope.sharedVar(initial: 0)
                Invariant("AtMostOne") { value <= 1 }
                Do(Step.enter) { Goto(Step.choose) }
                Do(Step.choose) {
                    Choose(1...2) { choice in Assign(value, to: choice) }
                }
            })
        }
    }
}

@TLAModel
struct BlockedControl {
    enum Step: String, CaseIterable { case wait }
    static var spec: TLASpec {
        #spec("BlockedControl") {
            Algorithm("BlockedControl", scoped: { scope in
                let value = scope.sharedVar(initial: 0)
                Do(Step.wait, when: value == 1) {
                    Assign(value, to: 2)
                }
            })
        }
    }
}

@TLAModel
struct InvalidAssumption {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("InvalidAssumption") {
            Assume(false)
            Algorithm("InvalidAssumption", scoped: { scope in
                let value = scope.sharedVar(initial: 0)
                Do(Step.advance) { Assign(value, to: 1) }
            })
        }
    }
}
