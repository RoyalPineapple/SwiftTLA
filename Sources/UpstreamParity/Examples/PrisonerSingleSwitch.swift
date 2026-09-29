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

    private enum Step: String, CaseIterable { case WardenAction }

    package static var spec: TLASpec {
        #spec("Prisoner") { scope in
            Extends(.finiteSets, .naturals)
            let Prisoner = scope.parameter(as: Set<String>.self,
                in: Set<Set<String>>([Set(["Alice"]), Set(["Alice", "Bob", "Eve"])]))
            let Light_Unknown = scope.parameter(as: Bool.self, in: Set<Bool>([false, true]))
            let DesignatedCounter = Select(from: Prisoner) { _ in true }
            let NormalPrisoner = Prisoner.removing(DesignatedCounter)
            let SignalLimit = If(Light_Unknown, then: 2, else: 1)
            let VictoryThreshold = If(Light_Unknown,
                then: 2 * Prisoner.cardinality - 1, else: Prisoner.cardinality)

            let count = scope.sharedVar(initial: 1)
            let announced = scope.sharedVar(initial: false)
            let signalled = scope.sharedVar(initial:
                Dictionary<String, Int>.mapping(over: NormalPrisoner) { _ in 0 })
            let light = scope.sharedVar(in: If(Light_Unknown,
                then: SetExpr<Light>.literal(.off, .on),
                else: SetExpr<Light>.literal(.off)))
            let has_visited = scope.sharedVar(initial: Set<String>())
            let TypeOK = Invariant()
            let VictoryOK = Invariant()
            let Terminating = Temporal()

            let wardenAction = Do(Step.WardenAction, over: Prisoner) { prisoner in
                If(prisoner == DesignatedCounter) {
                    If(light == Light.on) {
                        Assign(light, to: Light.off)
                        Assign(count, to: count + 1)
                    }
                    Assign(announced, to: count >= VictoryThreshold)
                } else: {
                    If(light == Light.off && signalled[prisoner] < SignalLimit) {
                        Assign(light, to: Light.on)
                        Assign(signalled[prisoner], to: signalled[prisoner] + 1)
                    }
                }
                Assign(has_visited, to: has_visited.inserting(prisoner))
            }
            wardenAction
            WeakFairness(each: wardenAction)

            TypeOK {
                IntRange(1, through: VictoryThreshold + 1).contains(count)
                    && SetExpr<Bool>.literal(false, true).contains(announced)
                    && Functions(from: NormalPrisoner, to: IntRange(0, through: 2)).contains(signalled)
                    && SetExpr<Light>.literal(.off, .on).contains(light)
                    && has_visited.isSubset(of: Prisoner)
            }
            VictoryOK { !announced || has_visited == Prisoner }
            Terminating(.eventually(announced))

            Validation("Prisoner") {
                Bind(Prisoner, to: Set<String>(["Alice", "Bob", "Eve"]))
                Bind(Light_Unknown, to: false)
            }
            Validation("PrisonerLightUnknown") {
                Bind(Prisoner, to: Set<String>(["Alice", "Bob", "Eve"]))
                Bind(Light_Unknown, to: true)
            }
            Validation("PrisonerSolo") {
                Bind(Prisoner, to: Set<String>(["Alice"]))
                Bind(Light_Unknown, to: false)
            }
            Validation("PrisonerSoloLightUnknown") {
                Bind(Prisoner, to: Set<String>(["Alice"]))
                Bind(Light_Unknown, to: true)
            }
        }
    }
}
