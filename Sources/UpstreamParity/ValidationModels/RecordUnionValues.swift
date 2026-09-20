import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct RecordUnionOrderingModel {
    package struct First: Hashable, Sendable { package let a: Int; package let z: Int }
    package struct Second: Hashable, Sendable { package let a: Int; package let b: Int }
    package struct Third: Hashable, Sendable { package let a: [Int]; package let c: Bool }
    package typealias Tail = OneOf<Second, Third>
    package typealias Value = OneOf<First, Tail>
    enum Step: String, CaseIterable { case finish }

    package static var spec: TLASpec {
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
            Validation("All record alternatives") {}
        }
    }
}

@TLAModel
package struct RecordUnionFieldDomainModel {
    package struct Count: Hashable, Sendable { package let value: Int }
    package struct Flag: Hashable, Sendable { package let value: Bool }
    package typealias Value = OneOf<Count, Flag>
    enum Step: String, CaseIterable { case finish }

    package static var spec: TLASpec {
        #spec("RecordUnionFieldDomain") { scope in
            let value = scope.sharedVar(in: Set<Value>([
                Value.second(Flag(value: true)), Value.first(Count(value: 0)),
                Value.second(Flag(value: false)), Value.first(Count(value: -1))
            ]))
            Algorithm("SelectRecord") {
                Do(Step.finish) { Assign(value, to: value); Stop() }
            }
            Validation("All field domains") {}
        }
    }
}
