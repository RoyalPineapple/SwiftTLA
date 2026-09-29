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

    private enum Step: String, CaseIterable { case CounterStep, NonCounterStep }

    package static var spec: TLASpec {
        #spec("Prisoners") { scope in
            Extends(.naturals, .finiteSets)
            let Prisoner = scope.parameter(as: Set<PrisonerID>.self,
                in: Subsets(of: Set<PrisonerID>([.p1, .p2, .p3, .p4])))
            let Counter = scope.parameter(as: PrisonerID.self, in: PrisonerID.all)
            Assume(Prisoner.contains(Counter) && Prisoner.cardinality > 1)
            let OtherPrisoner = Prisoner.removing(Counter)
            let switchAUp = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let switchBUp = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
            let timesSwitched = scope.sharedVar(initial:
                Dictionary<PrisonerID, Int>.mapping(over: OtherPrisoner) { _ in 0 })
            let count = scope.sharedVar(initial: 0)
            let TypeOK = Invariant()
            let CountInvariant = Invariant()
            let Safety = Temporal()
            let Liveness = Temporal()

            let counterStep = Do(Step.CounterStep) {
                If(switchAUp) {
                    Assign(switchAUp, to: false)
                    Assign(count, to: count + 1)
                } else: {
                    Assign(switchBUp, to: !switchBUp)
                }
            }
            counterStep
            let nonCounterStep = Do(Step.NonCounterStep, over: OtherPrisoner) { prisoner in
                If(!switchAUp && timesSwitched[prisoner] < 2) {
                    Assign(switchAUp, to: true)
                    Assign(timesSwitched[prisoner], to: timesSwitched[prisoner] + 1)
                } else: {
                    Assign(switchBUp, to: !switchBUp)
                }
            }
            nonCounterStep

            WeakFairness(counterStep)
            WeakFairness(each: nonCounterStep)

            let done = count == 2 * (Prisoner.cardinality - 1)
            TypeOK {
                SetExpr<Bool>.literal(false, true).contains(switchAUp)
                    && SetExpr<Bool>.literal(false, true).contains(switchBUp)
                    && Functions(from: OtherPrisoner, to: IntRange(0, through: 2)).contains(timesSwitched)
                    && IntRange(0, through: 2 * Prisoner.cardinality - 1).contains(count)
            }
            CountInvariant {
                let total = LetRec("sum", over: Subsets(of: OtherPrisoner), taking: Set<PrisonerID>.self,
                    { sum, remaining in
                        If(remaining.isEmpty, then: 0, else:
                            timesSwitched[Select(from: remaining) { _ in true }]
                                + sum(remaining.removing(Select(from: remaining) { _ in true })))
                    }, in: { sum in sum(OtherPrisoner) })
                let oneIfUp = If(switchAUp, then: 1, else: 0)
                SetExpr<Int>.literal(total - oneIfUp, total - oneIfUp + 1).contains(count)
            }
            Safety(.always(!done || ForAll(in: OtherPrisoner) { prisoner in
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
