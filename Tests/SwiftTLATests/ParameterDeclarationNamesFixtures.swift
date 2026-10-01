import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct LabeledParametersModel {
    enum Step: String, CaseIterable { case visit }

    static var spec: TLASpec {
        #spec("LabeledParameters") { scope in
            let limit = scope.parameter(as: Int.self, in: 0...2, label: "Visit limit")
            let enabled = scope.parameter(as: Bool.self)
            let count = scope.sharedVar(initial: 0)
            Algorithm("Visits") {
                Do(Step.visit, when: enabled && count < limit) {
                    Assign(count, to: count + 1)
                }
            }
            Validation("One visit") {
                Bind(limit, to: 1)
                Bind(enabled, to: true)
            }
        }
    }
}
