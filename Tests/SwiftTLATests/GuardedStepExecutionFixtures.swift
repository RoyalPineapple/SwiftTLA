import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct GuardedAlgorithm {
    enum Step: String, CaseIterable { case choose, finish }

    static var spec: TLASpec {
        #spec("GuardedAlgorithm") {
            Algorithm("GuardedAlgorithm", scoped: { scope in
                let ready = scope.sharedVar(in: 0...1)
                let value = scope.sharedVar(initial: 0)
                Do(Step.choose, when: ready == 1) {
                    Assign(value, to: 1 / ready)
                    Choose(1...2) { choice in Assign(value, to: value * choice) }
                    Goto(Step.finish)
                }
                Do(Step.finish) { Stop() }
            })
        }
    }
}

@TLAModel
struct GuardedProcesses {
    enum Node: String, CaseIterable, FiniteTLAValueDomain { case first, second }
    enum Step: String, CaseIterable { case enter, body, finish }
    enum Routine: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("GuardedProcesses") {
            Algorithm("GuardedProcesses", scoped: { scope in
                let entryReady = scope.sharedVar(in: 0...1)
                let bodyReady = scope.sharedVar(in: 0...1)
                let value = scope.sharedVar(initial: 0)
                Procedure(Routine.choose, parameters: Int.self) { divisor in
                    Do(Step.body, when: divisor > 0) {
                        Assign(value, to: 1 / divisor)
                        Choose(1...2) { choice in Assign(value, to: value * choice) }
                        Return()
                    }
                }
                Each(Node.all) { _ in
                    Do(Step.enter, when: entryReady == 1) {
                        Assign(value, to: 1 / entryReady)
                        Call(Routine.choose, with: bodyReady.expr)
                    }
                    Do(Step.finish) { Stop() }
                }
            })
        }
    }
}
