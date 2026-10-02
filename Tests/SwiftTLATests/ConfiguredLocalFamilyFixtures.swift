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
            let publish = Algorithm(label: "Publish") {
                Each(members, scoped: { member, process in
                    let value = process.localVar(initial: member + 10)
                    let family = value.family(for: Int.self)
                    let familyValid = family.keys == members
                        && ForAll(in: members) { other in family[other] == other + 10 }
                    Do(Step.publish) {
                        Assign(value, to: member + 11)
                    }
                    Family { familyValid }
                })
            }
            publish
            let empty = Validation(label: "Empty") { Bind(members, to: Set<Int>([])) }
            empty
            let one = Validation(label: "One") { Bind(members, to: Set<Int>([7])) }
            one
            let sparse = Validation(label: "Sparse") { Bind(members, to: Set<Int>([2, 5])) }
            sparse
        }
    }
}
