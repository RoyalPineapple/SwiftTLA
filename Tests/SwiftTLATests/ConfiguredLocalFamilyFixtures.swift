import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConfiguredLocalFamilyModel: Sendable {
    enum Step: String, CaseIterable { case publish }

    static var spec: TLASpec {
        #spec("ConfiguredLocalFamily") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([7]), Set<Int>([2, 5])]))
            let Family = Invariant()
            Algorithm("Publish") {
                Each(members, scoped: { member, process in
                    let value = process.localVar(initial: member + 10)
                    Do(Step.publish) {
                        Assign(value, to: member + 10)
                    }
                    Family {
                        value.family(for: Int.self).keys == members
                            && ForAll(in: members) { other in
                                value.family(for: Int.self)[other] == other + 10
                            }
                    }
                })
            }
            Validation("Empty") { Bind(members, to: Set<Int>([])) }
            Validation("One") { Bind(members, to: Set<Int>([7])) }
            Validation("Sparse") { Bind(members, to: Set<Int>([2, 5])) }
        }
    }
}
