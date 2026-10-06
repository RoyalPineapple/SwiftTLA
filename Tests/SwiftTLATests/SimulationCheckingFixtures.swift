import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct RevisitedStateCheckingLevelModel {
    enum Step: String, CaseIterable { case loop }

    static var spec: TLASpec {
        #spec("RevisitedStateCheckingLevel") { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.loop) { Assign(value, to: value) }
            Invariant("BeforeThirdState") { scope.checkingLevel < 3 }
        }
    }
}

@TLAModel
struct CandidateSafetySimulationModel {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("CandidateSafetySimulation") { scope in
            let value = scope.sharedVar(initial: 2)
            Do(Step.choose) {
                With(IntRange(0, through: 1)) { choice in
                    Assign(value, to: choice)
                }
            }
            Invariant("NonZero") { value != 0 }
        }
    }
}

struct LastCandidateGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 { .max }
}
