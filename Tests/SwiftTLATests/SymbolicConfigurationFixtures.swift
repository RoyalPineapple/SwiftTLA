import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SymbolicConfigurationModel: Sendable {
    enum Step: String, CaseIterable { case append }

    static var spec: TLASpec {
        #spec("SymbolicConfiguration") { model in
            let members = model.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1, 2])]))
            let input = model.parameter(as: [Int].self, in: Sequences(of: members))
            let limit = model.parameter(as: Int.self, in: 0...1_000_000_000)
            Algorithm("SymbolicConfiguration", scoped: { scope in
                let sequence: SharedVariable<[Int]> = scope.sharedVar(initial: input)
                Invariant("Elements") { Sequences(of: members).contains(sequence) }
                Do(Step.append) {
                    When(sequence.count < limit && members.contains(1))
                    Assign(sequence, to: sequence.appending(1))
                }
            })
            Validation("Example") {
                Bind(members, to: Set<Int>([1, 2]))
                Bind(input, to: Array<Int>([1, 2]))
                Bind(limit, to: 1_000_000_000)
            }
        }
    }
}
