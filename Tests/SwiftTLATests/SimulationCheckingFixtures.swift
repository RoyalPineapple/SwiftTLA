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

@TLAModel
struct ConstrainedInitialSafetySimulationModel {
    static var spec: TLASpec {
        #spec("ConstrainedInitialSafetySimulation") { scope in
            let value = scope.sharedVar(in: IntRange(0, through: 1))
            Constraint(value == 0)
            Invariant("OnlyZero") { value == 0 }
        }
    }
}

struct FirstCandidateGenerator: RandomNumberGenerator {
    mutating func next() -> UInt64 { 0 }
}

@TLAModel
struct LaterTraceSafetySimulationModel {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("LaterTraceSafetySimulation") { scope in
            let value = scope.sharedVar(initial: 2)
            Do(Step.choose) {
                When(value != 0)
                With(IntRange(0, through: 1)) { choice in
                    Assign(value, to: If(value == 2, then: choice, else: -1))
                }
            }
            Invariant("NonNegative") { value >= 0 && scope.checkingLevel <= 3 }
        }
    }
}

struct LaterTraceCandidateGenerator: RandomNumberGenerator {
    private var draws = 0

    mutating func next() -> UInt64 {
        defer { draws += 1 }
        return draws < 2 ? 0 : .max
    }
}
