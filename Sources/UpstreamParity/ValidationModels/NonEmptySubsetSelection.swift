import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct NonEmptySubsetSelectionModel: Sendable {
    package enum Step: String, CaseIterable { case keep }

    package static var spec: TLASpec {
        #spec("NonEmptySubsetSelection") { model in
            let members = model.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([1, 2]), Set<Int>([1, 2, 3])]))
            let selection = Algorithm(scoped: { scope in
                let selectedKeys = scope.sharedVar(in: NonEmptySubsets(of: members))
                Do(Step.keep) { Assign(selectedKeys, to: selectedKeys.expr) }
            })
            selection
            let twoMembers = Validation { Bind(members, to: Set<Int>([1, 2])) }
            twoMembers
            let threeMembers = Validation { Bind(members, to: Set<Int>([1, 2, 3])) }
            threeMembers
        }
    }
}
