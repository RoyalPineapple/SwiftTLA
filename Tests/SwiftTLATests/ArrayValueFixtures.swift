import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ArrayValueMachine {
    enum Choice: String, CaseIterable, FiniteTLAValueDomain {
        case one, two
        static let finiteValues = allCases
        static var defaultValue: Self { .one }
        var tlaValue: TLAValue { .constant(rawValue) }
    }
    enum Step: String, CaseIterable { case adopt, remove, select }

    static var spec: TLASpec {
        #spec("ArrayValueMachine") { scope in
            let input = scope.parameter(as: [Int].self,
                in: Set<[Int]>([Array<Int>([]), Array<Int>([2, 1, 2])]))
            let row = scope.sharedVar(initial: Array<Int>([]))
            let choices = scope.sharedVar(initial: Array<Choice>([.one, .two, .one]))
            Do(Step.adopt) { Assign(row, to: input.appending(3)) }
            Do(Step.remove) {
                When(row.count > 0)
                Assign(row, to: row.removing(at: 1.expr))
            }
            Do(Step.select) { Assign(row, to: row.selecting { element in element != 2 }) }
            Invariant("Shape") { row.count <= 4 && choices.count == 3 && choices[1.expr] == Choice.one }
            Validation("Empty") { Bind(input, to: Array<Int>([])) }
            Validation("Repeated") { Bind(input, to: Array<Int>([2, 1, 2])) }
        }
    }
}
