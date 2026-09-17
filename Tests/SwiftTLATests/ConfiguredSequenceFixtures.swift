import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ConfiguredSequenceDomainMachine {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("ConfiguredSequenceDomainMachine") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>([]), Set<Int>([1]), Set<Int>([1, 2])]))
            let row = scope.sharedVar(in: Sequences(of: members, lengths: 0...2))
            let sorted = scope.sharedVar(in: SortedSequences(of: members, lengths: 0...2))
            let zeroBased = scope.sharedVar(in: ZeroBasedSequences(of: members, lengths: 0...2))
            Do(Step.stay) { Skip() }
            Invariant("Bounded") { row.count <= 2 && sorted.count <= 2 && zeroBased.count <= 2 }
            Validation("Empty") { Bind(members, to: Set<Int>([])) }
            Validation("One") { Bind(members, to: Set<Int>([1])) }
            Validation("Two") { Bind(members, to: Set<Int>([1, 2])) }
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
            let row = scope.sharedVar(in: Sequences(of: members, lengths: 0...2))
            Do(Step.stay) { Skip() }
            Invariant("Bounded") { row.count <= 2 }
            Validation("Nominal") { Bind(members, to: Set<Choice>([Choice.one, Choice.two])) }
        }
    }
}
