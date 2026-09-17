import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConfiguredSequenceDomainMachine {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("ConfiguredSequenceDomainMachine") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2])]))
            let lengths = scope.parameter(as: Set<Int>.self, in: Set<Set<Int>>([
                Set<Int>([]), Set<Int>([0]), Set<Int>([1, 2]), Set<Int>([0, 1, 2]), Set<Int>([-1, 0])
            ]))
            let row = scope.sharedVar(in: Sequences(of: members, lengths: lengths))
            let sorted = scope.sharedVar(in: SortedSequences(of: members, lengths: lengths))
            let zeroBased = scope.sharedVar(in: ZeroBasedSequences(of: members, lengths: lengths))
            Do(Step.stay) { Skip() }
            Invariant("Bounded") { row.count <= 2 && sorted.count <= 2 && zeroBased.count <= 2 }
            Validation("Empty") {
                Bind(members, to: Set<Int>([]))
                Bind(lengths, to: Set<Int>([0, 1, 2]))
            }
            Validation("One") {
                Bind(members, to: Set<Int>([1]))
                Bind(lengths, to: Set<Int>([0, 1, 2]))
            }
            Validation("Two") {
                Bind(members, to: Set<Int>([1, 2]))
                Bind(lengths, to: Set<Int>([0, 1, 2]))
            }
            Validation("Zero length") {
                Bind(members, to: Set<Int>([1, 2]))
                Bind(lengths, to: Set<Int>([0]))
            }
            Validation("Positive lengths") {
                Bind(members, to: Set<Int>([1, 2]))
                Bind(lengths, to: Set<Int>([1, 2]))
            }
        }
    }
}

@TLAModel
struct NominalSequenceMachine {
    enum Choice: String, CaseIterable, FiniteTLAValueDomain {
        case one, two
        static let finiteValues = allCases
        static var defaultValue: Self { .one }
        var tlaValue: TLAValue { .constant(rawValue) }
    }
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("NominalSequenceMachine") { scope in
            let members = scope.parameter(as: Set<Choice>.self,
                in: Set<Set<Choice>>([Set<Choice>([Choice.one, Choice.two])]))
            let limit = scope.parameter(as: Int.self, in: 0...2)
            let row = scope.sharedVar(in: Sequences(of: members, lengths: IntRange(0, through: limit)))
            Do(Step.stay) { Skip() }
            Invariant("Bounded") { row.count <= limit }
            Validation("Nominal") {
                Bind(members, to: Set<Choice>([Choice.one, Choice.two]))
                Bind(limit, to: 2)
            }
        }
    }
}
