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
            let NonNegative = Invariant()
            NonNegative { value >= 0 && scope.checkingLevel <= 3 }
            let sampled = Validation {}.checking(only: [NonNegative])
                .checkingDeadlock(false).simulating(traces: 2, maximumDepth: 2)
            sampled
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

@TLAModel
struct SampledTemporalViolationModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SampledTemporalViolation") { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.advance, when: value < 2) { Assign(value, to: value + 1) }
            let EventuallyThree = Temporal()
            EventuallyThree(.eventually(value == 3))
            let sampled = Validation {}.checking(only: [EventuallyThree])
                .checkingDeadlock(false).simulating(traces: 1, maximumDepth: 2)
                .expect(EventuallyThree, .violated)
            sampled
        }
    }
}

@TLAModel
struct SampledTemporalNonproofModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SampledTemporalNonproof") { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.advance, when: value == 0) { Assign(value, to: 1) }
            let EventuallyZero = Temporal()
            EventuallyZero(.eventually(value == 0))
            let sampled = Validation {}.checking(only: [EventuallyZero])
                .checkingDeadlock(false).simulating(traces: 1, maximumDepth: 1)
            sampled
        }
    }
}

@TLAModel
struct SampledFairTemporalModel {
    enum Step: String, CaseIterable { case advance, stay }

    static var spec: TLASpec {
        #spec("SampledFairTemporal") { scope in
            let value = scope.sharedVar(initial: 0)
            let advance = Do(Step.advance, when: value == 0) { Assign(value, to: 1) }
            let stay = Do(Step.stay) { Skip() }
            advance
            stay
            WeakFairness(advance)
            let EventuallyOne = Temporal()
            EventuallyOne(.eventually(value == 1))
            let sampled = Validation {}.checking(only: [EventuallyOne])
                .checkingDeadlock(false).simulating(traces: 1, maximumDepth: 1)
            sampled
        }
    }
}
