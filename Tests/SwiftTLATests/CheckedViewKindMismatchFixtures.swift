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

@TLAModel
struct NestedCheckedRecordView {
    enum Step: String, CaseIterable { case inspect }
    struct Source: Hashable, Sendable { let nested: Int }
    struct Expected: Hashable, Sendable { let nested: [Int] }

    static var spec: TLASpec {
        #spec("NestedCheckedRecordView") {
            let model = Algorithm(label: "NestedCheckedRecordView", scoped: { scope in
                let record = scope.sharedVar(_name: "record", initial: Source(nested: 1))
                Do(Step.inspect, when: record.expr.assuming(Expected.self).nested.count == 0) {}
            })
            model
        }
    }
}

@TLAModel
struct NestedCheckedSequenceView {
    enum Step: String, CaseIterable { case inspect }

    static var spec: TLASpec {
        #spec("NestedCheckedSequenceView") {
            let model = Algorithm(label: "NestedCheckedSequenceView", scoped: { scope in
                let numbers = scope.sharedVar(_name: "numbers", initial: [1])
                Do(Step.inspect, when: numbers.expr.assuming(Array<Array<Int>>.self) == [[1]]) {}
            })
            model
        }
    }
}
