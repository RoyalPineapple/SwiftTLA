import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/Prisoners/Prisoners.tla, Prisoners.cfg.
@TLAModel
package struct PrisonersModel: Sendable {
    package enum PrisonerID: String, CaseIterable, FiniteTLAValueDomain {
        case p1, p2, p3, p4

        package static var defaultValue: Self { .p1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case counterStep = "CounterStep"
        case nonCounterStep = "NonCounterStep"
    }

    package static var spec: TLASpec {
        #spec("Prisoners") { scope in
            Extends(.naturals, .finiteSets)
            let Prisoner = scope.parameter(as: Set<PrisonerID>.self,
                in: Subsets(of: Set<PrisonerID>([.p1, .p2, .p3, .p4])))
            let Counter = scope.parameter(as: PrisonerID.self, in: PrisonerID.all)
            Assume(Prisoner.contains(Counter) && Prisoner.count > 1)
            let OtherPrisoner = Prisoner.removing(Counter)
            let switchAUp = scope.sharedVar(initiallyIn: Bool.all)
            let switchBUp = scope.sharedVar(initiallyIn: Bool.all)
            let timesSwitched = scope.sharedVar(initial:
                Dictionary<PrisonerID, Int>.mapping(over: OtherPrisoner) { _ in 0 })
            let count = scope.sharedVar(initial: 0)
            let Safety = Temporal()
            let Liveness = Temporal()

            let counterStep = Do(Step.counterStep) {
                If(switchAUp) {
                    switchAUp.set(false)
                    count += 1
                } else: {
                    switchBUp.set(!switchBUp)
                }
            }
            counterStep
            let nonCounterStep = Do(Step.nonCounterStep, over: OtherPrisoner) { prisoner in
                If(!switchAUp && timesSwitched[prisoner] < 2) {
                    switchAUp.set(true)
                    timesSwitched[prisoner] += 1
                } else: {
                    switchBUp.set(!switchBUp)
                }
            }
            nonCounterStep

            WeakFairness(counterStep)
            WeakFairness(each: nonCounterStep)

            let done = count == 2 * (Prisoner.count - 1)
            Invariant("TypeOK") {
                Bool.all.contains(switchAUp)
                    && Bool.all.contains(switchBUp)
                    && Functions(from: OtherPrisoner, to: IntRange(0, through: 2)).contains(timesSwitched)
                    && IntRange(0, through: 2 * Prisoner.count - 1).contains(count)
            }
            Invariant("CountInvariant") {
                let total = LetRec("sum", over: Subsets(of: OtherPrisoner), taking: Set<PrisonerID>.self,
                    { sum, remaining in
                        If(remaining.isEmpty, then: 0, else:
                            timesSwitched[Select(from: remaining) { _ in true }]
                                + sum(remaining.removing(Select(from: remaining) { _ in true })))
                    }, in: { sum in sum(OtherPrisoner) })
                let oneIfUp = If(switchAUp, then: 1, else: 0)
                SetExpr<Int>.literal(total - oneIfUp, total - oneIfUp + 1).contains(count)
            }
            Safety(.always(!done || OtherPrisoner.allSatisfy { prisoner in
                timesSwitched[prisoner] > 0
            }))
            Liveness(.eventually(done))

            Validation("Prisoners") {
                Bind(Prisoner, to: Set<PrisonerID>([.p1, .p2, .p3, .p4]))
                Bind(Counter, to: PrisonerID.p1)
            }
        }
    }
}
