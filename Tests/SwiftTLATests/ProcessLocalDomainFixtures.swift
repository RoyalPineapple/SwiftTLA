import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct IndependentLocalChoices: Sendable {
    private enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("IndependentLocalChoices") {
            Algorithm("IndependentLocalChoices") {
                Each(Set<Int>([1, 2]), scoped: { (_: ProcessIdentifier<Int>, scope: ProcessScope) in
                    let choice = scope.localVar(in: Subsets(of: Set<Int>([1, 2])))
                    Do(Step.stay) { Assign(choice, to: choice) }
                })
            }
        }
    }
}
