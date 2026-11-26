// Prisoners signal visits with two switches so a designated counter can count the group.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/Prisoners/Prisoners.tla

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
        case countSignalOrFlipSwitchB = "CounterStep"
        case signalCounterOrFlipSwitchB = "NonCounterStep"
    }

    package static var spec: TLASpec {
        #spec("Prisoners") { scope in
            Extends(.naturals, .finiteSets)
            let prisoners = scope.parameter(tlaName: "Prisoner", as: Set<PrisonerID>.self,
                in: Subsets(of: Set<PrisonerID>([.p1, .p2, .p3, .p4])))
            let designatedCounter = scope.parameter(tlaName: "Counter", as: PrisonerID.self, in: PrisonerID.all)
            Assume(prisoners.contains(designatedCounter) && prisoners.count > 1)
            let otherPrisoners = prisoners.removing(designatedCounter)
            let switchAUp = scope.sharedVar(initiallyIn: Bool.all)
            let switchBUp = scope.sharedVar(initiallyIn: Bool.all)
            let timesSwitched = scope.sharedVar(initial:
                Dictionary<PrisonerID, Int>.mapping(over: otherPrisoners) { _ in 0 })
            let count = scope.sharedVar(initial: 0)
            let Safety = Temporal()
            let Liveness = Temporal()

            let countSignalOrFlipSwitchB = Do(Step.countSignalOrFlipSwitchB) {
                If(switchAUp) {
                    switchAUp.set(false)
                    count += 1
                } else: {
                    switchBUp.set(!switchBUp)
                }
            }
            let signalCounterOrFlipSwitchB = Do(Step.signalCounterOrFlipSwitchB, over: otherPrisoners) { prisoner in
                If(!switchAUp && timesSwitched[prisoner] < 2) {
                    switchAUp.set(true)
                    timesSwitched[prisoner] += 1
                } else: {
                    switchBUp.set(!switchBUp)
                }
            }

            WeakFairness(countSignalOrFlipSwitchB)
            WeakFairness(each: signalCounterOrFlipSwitchB)

            let done = count == 2 * (prisoners.count - 1)
            Invariant("TypeOK") {
                Bool.all.contains(switchAUp)
                    && Bool.all.contains(switchBUp)
                    && Functions(from: otherPrisoners, to: IntRange(0, through: 2)).contains(timesSwitched)
                    && IntRange(0, through: 2 * prisoners.count - 1).contains(count)
            }
            Invariant("CountInvariant") {
                let total = LetRec("sum", over: Subsets(of: otherPrisoners), taking: Set<PrisonerID>.self,
                    { sum, remaining in
                        If(remaining.isEmpty, then: 0, else:
                            timesSwitched[Select(from: remaining) { _ in true }]
                                + sum(remaining.removing(Select(from: remaining) { _ in true })))
                    }, in: { sum in sum(otherPrisoners) })
                let oneIfUp = If(switchAUp, then: 1, else: 0)
                SetExpr<Int>.literal(total - oneIfUp, total - oneIfUp + 1).contains(count)
            }
            Safety(.always(!done || otherPrisoners.allSatisfy { prisoner in
                timesSwitched[prisoner] > 0
            }))
            Liveness(.eventually(done))

            Validation("Prisoners") {
                Bind(prisoners, to: Set<PrisonerID>([.p1, .p2, .p3, .p4]))
                Bind(designatedCounter, to: PrisonerID.p1)
            }
        }
    }
}
