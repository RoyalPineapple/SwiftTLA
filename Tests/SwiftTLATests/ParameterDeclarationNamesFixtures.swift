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
            let visits = Algorithm(label: "Visits") {
                Do(Step.visit, when: enabled && count < limit) {
                    Assign(count, to: count + 1)
                }
            }
            visits
            let oneVisit = Validation(label: "One visit") {
                Bind(limit, to: 1)
                Bind(enabled, to: true)
            }
            oneVisit
        }
    }
}

@TLAModel
struct UpstreamDeclarationNames {
    enum Step: String, CaseIterable { case publish }

    static var spec: TLASpec {
        #spec("UpstreamDeclarationNames") { scope in
            let writerSets = Set<Set<Int>>([Set<Int>([1, 2])])
            let writers = scope.parameter(tlaName: "Writers", as: Set<Int>.self, in: writerSets)
            let published = scope.sharedVar(initial: -1)
            let nextSequence = scope.sharedVar(tlaName: "next_sequence", initial: 0)
            Do(Step.publish) {
                When(writers.contains(1) && nextSequence == 0)
                published.set(nextSequence)
                nextSequence.set(nextSequence + 1)
            }
            Invariant("Unpublished") { nextSequence == 0 }
            Validation("TwoWriters") { Bind(writers, to: Set<Int>([1, 2])) }
        }
    }
}
