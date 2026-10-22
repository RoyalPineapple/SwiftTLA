import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct IncompatibleCheckedRecordView {
    enum Step: String, CaseIterable { case inspect }
    struct Record: Hashable, Sendable { let count: Int }

    static var spec: TLASpec {
        #spec("IncompatibleCheckedRecordView") {
            let model = Algorithm(label: "IncompatibleCheckedRecordView", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 1)
                Do(Step.inspect, when: count.expr.assuming(Record.self).count == 0) {}
            })
            model
        }
    }
}
