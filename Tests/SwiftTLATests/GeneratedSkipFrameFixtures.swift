import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedSkipFrameModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("GeneratedSkipFrameModel") { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.stay) { Skip() }
            Invariant("Preserved") { value == 0 }
        }
    }
}
