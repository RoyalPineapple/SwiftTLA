import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct FunctionUpdateMachine {
    enum Process: String, CaseIterable, FiniteTLAValueDomain {
        case first, second
        static let finiteValues = allCases
        static var defaultValue: Self { .first }
    }
    enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case initial, done
        static let finiteValues = allCases
        static var defaultValue: Self { .initial }
    }
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("FunctionUpdateMachine") { scope in
            let phases: SharedVariable<[Process: Phase]> = scope.sharedVar(
                initial: [.first: .initial, .second: .initial])
            Do(Step.advance, over: Process.all) { process in
                When(phases[process] == Phase.initial)
                Assign(phases[process], to: Phase.done)
            }
        }
    }
}
