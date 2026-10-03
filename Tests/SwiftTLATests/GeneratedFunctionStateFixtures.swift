import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GeneratedFunctionStateModel {
    enum Key: Int, CaseIterable, FiniteTLAValueDomain {
        case one = 1, two = 2

        static let finiteValues = allCases
        static var defaultValue: Self { .one }
    }

    enum Step: String, CaseIterable { case replace }

    static var spec: TLASpec {
        #spec("GeneratedFunctionStateModel") { scope in
            let clock = scope.sharedVar(initial: Function<Key, Int>.literal((.one, 0), (.two, 0)))
            Do(Step.replace) {
                When(clock[.one] == 0)
                Assign(clock, to: Function<Key, Int>.mapping { key in
                    If(key == Key.one, then: 10, else: 20)
                })
            }
        }
    }
}
