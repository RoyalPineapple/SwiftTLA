// This version adds the current stage and cycle to the PCR reaction model.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/glowingRaccoon/stages.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct GlowingStagesModel: Sendable {
    private enum Step: String, CaseIterable { case heat, cool, anneal, extend }

    package static var spec: TLASpec {
        #spec("stages") { scope in
            Extends(.naturals)
            let DNA = scope.parameter(as: Int.self, in: 5...5)
            let PRIMER = scope.parameter(as: Int.self, in: 5...5)
            let tee = scope.sharedVar(initial: "Hot")
            let primer = scope.sharedVar(initial: PRIMER)
            let dna = scope.sharedVar(initial: DNA)
            let template = scope.sharedVar(initial: 0)
            let hybrid = scope.sharedVar(initial: 0)
            let stage = scope.sharedVar(initial: "init")
            let cycle = scope.sharedVar(initial: 0)

            let heat = Do(Step.heat, when: tee == "Hot" && (stage == "init" || stage == "extended")) {
                stage.set("denatured")
                tee.set("TooHot")
                primer.set(primer + hybrid)
                template.set(template + hybrid + 2 * dna)
                dna.set(0)
                hybrid.set(0)
            }
            heat
            let cool = Do(Step.cool, when: tee == "TooHot" && stage == "denatured") {
                tee.set("Hot")
                stage.set("ready")
            }
            cool
            let anneal = Do(Step.anneal, when: tee == "Hot" && stage == "ready") {
                With(IntRange(1, through: If(primer < template, then: primer, else: template))) { k in
                    tee.set("Warm")
                    stage.set("annealed")
                    primer.set(primer - k)
                    template.set(template - k)
                    hybrid.set(hybrid + k)
                }
            }
            anneal
            let extend = Do(Step.extend, when: tee == "Warm" && stage == "annealed") {
                stage.set("extended")
                cycle += 1
                tee.set("Hot")
                dna.set(dna + hybrid)
                hybrid.set(0)
            }

            extend
            WeakFairness(anneal)
            WeakFairness(heat)
            WeakFairness(cool)
            WeakFairness(extend)

            let TypeOK = Invariant()
            TypeOK {
                Set<String>(["Warm", "Hot", "TooHot"]).contains(tee)
                primer >= 0 && dna >= 0 && template >= 0 && hybrid >= 0 && cycle >= 0
                Set<String>(["init", "ready", "annealed", "extended", "denatured"]).contains(stage)
            }
            let cleanInstance = Instance(of: GlowingCleanModel.self) {
                Bind(\.DNA, to: DNA)
                Bind(\.PRIMER, to: PRIMER)
            }
            cleanInstance
            let cleanSpec = Refinement(instance: cleanInstance) {
                Map(\.tee, projecting: tee)
                Map(\.primer, from: primer)
                Map(\.dna, from: dna)
                Map(\.template, from: template)
                Map(\.hybrid, from: hybrid)
            }
            cleanSpec
            let primerDepleted = Temporal()
            primerDepleted(.eventually(primer == 0))

            Validation("Upstream") {
                Bind(DNA, to: 5)
                Bind(PRIMER, to: 5)
            }.checkingDeadlock(false)
            Validation("APstages") {
                Bind(DNA, to: 5)
                Bind(PRIMER, to: 5)
            }
                .checking(only: [TypeOK]).checkingDeadlock(false)
        }
    }
}
