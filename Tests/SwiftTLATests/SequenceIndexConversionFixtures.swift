import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SequenceIndexConversionMachine: Sendable {
    enum Element: String, CaseIterable, FiniteTLAValueDomain, Sendable { case first, second }
    enum Step: String, CaseIterable, Sendable { case rotate }

    static var spec: TLASpec {
        #spec("SequenceIndexConversionMachine") { scope in
            let input = scope.parameter(as: [Int].self,
                in: Set<[Int]>([Array<Int>([]), Array<Int>([7]), Array<Int>([3, 1, 3])]))
            let agrees = Invariant()
            Import(ZSequences.module, configuring: ZSequences.boundedNaturalNumbers(through: 3))
            let rootMembers = scope.sharedVar(initial: ZSequences.oneBased(from:
                ZSequences.zeroBased(from: Array<Element>([.second, .first, .second]))))
            let conversion = Algorithm(label: "Conversion", scoped: { algorithm in
                let zero = algorithm.sharedVar(initial: ZSequences.zeroBased(from: input))
                let one = algorithm.sharedVar(initial: ZSequences.oneBased(from: zero))
                let empty = algorithm.sharedVar(initial: ZSequences.oneBased(from:
                    ZSequences.zeroBased(from: Array<Int>([]))))
                let members = algorithm.sharedVar(initial: ZSequences.oneBased(from:
                    ZSequences.zeroBased(from: rootMembers)))
                Do(Step.rotate) {
                    Assign(zero, to: ZSequences.rotation(of: zero, leftBy: 1))
                    Assign(one, to: ZSequences.oneBased(from: zero))
                    Goto(Step.rotate)
                }
                agrees { one == ZSequences.oneBased(from: zero) && members.count == 3 && empty.count == 0 }
            })
            conversion
            let empty = Validation(label: "Empty") { Bind(input, to: Array<Int>([])) }
            empty
            let single = Validation(label: "Single") { Bind(input, to: Array<Int>([7])) }
            single
            let repeated = Validation(label: "Repeated") { Bind(input, to: Array<Int>([3, 1, 3])) }
            repeated
        }
    }
}
