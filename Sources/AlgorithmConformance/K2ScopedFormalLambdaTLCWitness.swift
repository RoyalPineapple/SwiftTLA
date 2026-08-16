import SwiftTLA
import SwiftTLAMacros

/// Bounded K2 witness for a process binding used as a formal-lambda argument.
@TLAModel
public struct K2ScopedFormalLambdaTLCWitness {
    public enum Worker: String, CaseIterable, FiniteDomainKey {
        case left
        case right

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "k2.scoped-formal-lambda-tlc-witness.worker")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("K2ScopedFormalLambdaTLCWitness") {
            Algorithm("K2ScopedFormalLambdaTLCWitness") {
                let counters = SharedVar(initial: Function<Worker, Int>.literal(
                    (.left, 0),
                    (.right, 0)
                ))

                Each(Worker.all) { worker in
                    Do("advance") {
                        Assign(counters, to: counters.updating(worker, to: Expr<Int>(
                            StateExpr.operatorApplication(
                                .lambda(FormalLambda(
                                    parameters: ["value"],
                                    body: StateExpr.variable("value") + 1
                                )),
                                [.value(counters[worker].raw)]
                            )
                        )))
                    }
                }
            }
        }
    }
}
