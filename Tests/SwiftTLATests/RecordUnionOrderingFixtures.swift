import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RecordUnionOrderingModel {
    struct First: Hashable, Sendable { let a: Int; let z: Int }
    struct Second: Hashable, Sendable { let a: Int; let b: Int }
    struct Third: Hashable, Sendable { let a: [Int]; let c: Bool }
    typealias Tail = OneOf<Second, Third>
    typealias Value = OneOf<First, Tail>
    enum Step: String, CaseIterable { case finish }

    static var spec: TLASpec {
        #spec("RecordUnionOrdering") { scope in
            let value = scope.sharedVar(in: Set<Value>([
                Value.first(First(a: 2, z: 0)),
                Value.second(Tail.first(Second(a: 2, b: -1))),
                Value.second(Tail.second(Third(a: [1], c: true))),
                Value.first(First(a: 0, z: 2)),
                Value.second(Tail.first(Second(a: 1, b: 9))),
                Value.second(Tail.second(Third(a: [], c: false)))
            ]))
            Algorithm("SelectRecord") {
                Do(Step.finish) { Assign(value, to: value); Stop() }
            }
        }
    }
}

@TLAModel
struct RecordUnionFieldDomainModel {
    struct Count: Hashable, Sendable { let value: Int }
    struct Flag: Hashable, Sendable { let value: Bool }
    typealias Value = OneOf<Count, Flag>
    enum Step: String, CaseIterable { case finish }

    static var spec: TLASpec {
        #spec("RecordUnionFieldDomain") { scope in
            let value = scope.sharedVar(in: Set<Value>([
                Value.second(Flag(value: true)), Value.first(Count(value: 0)),
                Value.second(Flag(value: false)), Value.first(Count(value: -1))
            ]))
            Algorithm("SelectRecord") {
                Do(Step.finish) { Assign(value, to: value); Stop() }
            }
        }
    }
}
