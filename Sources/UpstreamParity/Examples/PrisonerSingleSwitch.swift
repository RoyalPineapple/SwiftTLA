// Prisoners use one shared switch to learn whether everyone has visited the room.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/Prisoners_Single_Switch/Prisoner.tla

import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/Prisoners_Single_Switch/Prisoner.tla.
@TLAModel
package struct PrisonerSingleSwitchModel: Sendable {
    package enum Light: String, CaseIterable, FiniteTLAValueDomain {
        case off, on

        package static var defaultValue: Self { .off }
        package static let finiteValues = allCases
    }

    private enum Step: String, CaseIterable { case visitSwitchRoom = "WardenAction" }

    package static var spec: TLASpec {
        #spec("Prisoner") { scope in
            Extends(.finiteSets, .naturals)
            let prisoners = scope.parameter(tlaName: "Prisoner", as: Set<String>.self,
                in: Set<Set<String>>([Set(["Alice"]), Set(["Alice", "Bob", "Eve"])]))
            let initialLightIsUnknown = scope.parameter(tlaName: "Light_Unknown", as: Bool.self)
            let designatedCounter = Select(from: prisoners) { _ in true }
            let otherPrisoners = prisoners.removing(designatedCounter)
            let signalLimit = If(initialLightIsUnknown, then: 2, else: 1)
            let victoryThreshold = If(initialLightIsUnknown,
                then: 2 * prisoners.count - 1, else: prisoners.count)

            let count = scope.sharedVar(initial: 1)
            let announced = scope.sharedVar(initial: false)
            let signalled = scope.sharedVar(initial:
                Dictionary<String, Int>.mapping(over: otherPrisoners) { _ in 0 })
            let light = scope.sharedVar(initiallyIn: If(initialLightIsUnknown,
                then: SetExpr<Light>.literal(.off, .on),
                else: SetExpr<Light>.literal(.off)))
            let visitedPrisoners = scope.sharedVar(tlaName: "has_visited", initial: Set<String>())
            let Terminating = Temporal()

            let visitSwitchRoom = Do(Step.visitSwitchRoom, over: prisoners) { prisoner in
                If(prisoner == designatedCounter) {
                    If(light == Light.on) {
                        light.set(Light.off)
                        count += 1
                    }
                    announced.set(count >= victoryThreshold)
                } else: {
                    If(light == Light.off && signalled[prisoner] < signalLimit) {
                        light.set(Light.on)
                        signalled[prisoner] += 1
                    }
                }
                visitedPrisoners.insert(prisoner)
            }
            WeakFairness(each: visitSwitchRoom)

            Invariant("TypeOK") {
                IntRange(1, through: victoryThreshold + 1).contains(count)
                    && Bool.all.contains(announced)
                    && Functions(from: otherPrisoners, to: IntRange(0, through: 2)).contains(signalled)
                    && SetExpr<Light>.literal(.off, .on).contains(light)
                    && visitedPrisoners.isSubset(of: prisoners)
            }
            Invariant("VictoryOK") { !announced || visitedPrisoners == prisoners }
            Terminating(.eventually(announced))

            Validation("prisonerValidation", label: "Prisoner") {
                Bind(prisoners, to: ["Alice", "Bob", "Eve"])
                Bind(initialLightIsUnknown, to: false)
            }
            Validation("PrisonerLightUnknown") {
                Bind(prisoners, to: ["Alice", "Bob", "Eve"])
                Bind(initialLightIsUnknown, to: true)
            }
            Validation("PrisonerSolo") {
                Bind(prisoners, to: ["Alice"])
                Bind(initialLightIsUnknown, to: false)
            }
            Validation("PrisonerSoloLightUnknown") {
                Bind(prisoners, to: ["Alice"])
                Bind(initialLightIsUnknown, to: true)
            }
        }
    }
}
