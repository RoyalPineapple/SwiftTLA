import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ParameterizedActorModel {
    enum Step: String, CaseIterable { case pass }

    static var spec: TLASpec {
        #spec { scope in
            let leader = scope.sharedVar(initial: 1)
            let turn = scope.sharedVar(initial: 0)
            Do(Step.pass, over: Set<Int>([1, 2]), Set<Int>([1, 2]), Set<Int>([1, 2, 3])) {
                from, to, round in
                When(leader == from && to != from && turn + 1 == round)
                Assign(leader, to: to)
                Assign(turn, to: round)
            }
        }
    }
}
