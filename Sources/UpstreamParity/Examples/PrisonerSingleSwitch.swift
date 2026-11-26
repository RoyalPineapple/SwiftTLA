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

    private enum Step: String, CaseIterable { case wardenAction = "WardenAction" }

    package static var spec: TLASpec {
        #spec("Prisoner") { scope in
            Extends(.finiteSets, .naturals)
            let Prisoner = scope.parameter(as: Set<String>.self,
                in: Set<Set<String>>([Set(["Alice"]), Set(["Alice", "Bob", "Eve"])]))
            let Light_Unknown = scope.parameter(as: Bool.self)
            let DesignatedCounter = Select(from: Prisoner) { _ in true }
            let NormalPrisoner = Prisoner.removing(DesignatedCounter)
            let SignalLimit = If(Light_Unknown, then: 2, else: 1)
            let VictoryThreshold = If(Light_Unknown,
                then: 2 * Prisoner.count - 1, else: Prisoner.count)

            let count = scope.sharedVar(initial: 1)
            let announced = scope.sharedVar(initial: false)
            let signalled = scope.sharedVar(initial:
                Dictionary<String, Int>.mapping(over: NormalPrisoner) { _ in 0 })
            let light = scope.sharedVar(initiallyIn: If(Light_Unknown,
                then: SetExpr<Light>.literal(.off, .on),
                else: SetExpr<Light>.literal(.off)))
            let has_visited = scope.sharedVar(initial: Set<String>())
            let Terminating = Temporal()

            let wardenAction = Do(Step.wardenAction, over: Prisoner) { prisoner in
                If(prisoner == DesignatedCounter) {
                    If(light == Light.on) {
                        light.set(Light.off)
                        count += 1
                    }
                    announced.set(count >= VictoryThreshold)
                } else: {
                    If(light == Light.off && signalled[prisoner] < SignalLimit) {
                        light.set(Light.on)
                        signalled[prisoner] += 1
                    }
                }
                has_visited.insert(prisoner)
            }
            WeakFairness(each: wardenAction)

            Invariant("TypeOK") {
                IntRange(1, through: VictoryThreshold + 1).contains(count)
                    && Bool.all.contains(announced)
                    && Functions(from: NormalPrisoner, to: IntRange(0, through: 2)).contains(signalled)
                    && SetExpr<Light>.literal(.off, .on).contains(light)
                    && has_visited.isSubset(of: Prisoner)
            }
            Invariant("VictoryOK") { !announced || has_visited == Prisoner }
            Terminating(.eventually(announced))

            Validation("prisonerValidation", label: "Prisoner") {
                Bind(Prisoner, to: ["Alice", "Bob", "Eve"])
                Bind(Light_Unknown, to: false)
            }
            Validation("PrisonerLightUnknown") {
                Bind(Prisoner, to: ["Alice", "Bob", "Eve"])
                Bind(Light_Unknown, to: true)
            }
            Validation("PrisonerSolo") {
                Bind(Prisoner, to: ["Alice"])
                Bind(Light_Unknown, to: false)
            }
            Validation("PrisonerSoloLightUnknown") {
                Bind(Prisoner, to: ["Alice"])
                Bind(Light_Unknown, to: true)
            }
        }
    }
}
