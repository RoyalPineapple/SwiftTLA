import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct GlowingProductModel: Sendable {
    private enum Step: String, CaseIterable { case heat, cool, anneal, extend }

    package static var spec: TLASpec {
        #spec("product") { scope in
            Extends(.naturals)
            let DNA = scope.parameter(as: Int.self, in: 5...5)
            let PRIMER = scope.parameter(as: Int.self, in: 5...5)
            let tee = scope.sharedVar(initial: "Hot")
            let primer = scope.sharedVar(initial: PRIMER)
            let longTemplate = scope.sharedVar(initial: 0)
            let shortTemplate = scope.sharedVar(initial: 0)
            let tinyTemplate = scope.sharedVar(initial: 0)
            let longHybrid = scope.sharedVar(initial: 0)
            let shortHybrid = scope.sharedVar(initial: 0)
            let tinyHybrid = scope.sharedVar(initial: 0)
            let longLongDouble = scope.sharedVar(initial: DNA)
            let shortLongDouble = scope.sharedVar(initial: 0)
            let tinyShortDouble = scope.sharedVar(initial: 0)
            let product = scope.sharedVar(initial: 0)
            let stage = scope.sharedVar(initial: "init")
            let cycle = scope.sharedVar(initial: 0)

            let templates = longTemplate + shortTemplate + tinyTemplate
            let hybrids = longHybrid + shortHybrid + tinyHybrid
            let doubles = longLongDouble + shortLongDouble + tinyShortDouble + product

            let heat = Do(Step.heat, when: tee == "Hot" && (stage == "init" || stage == "extended")) {
                stage.set("denatured")
                tee.set("TooHot")
                primer.set(primer + hybrids)
                longTemplate.set(longTemplate + longHybrid + shortLongDouble + 2 * longLongDouble)
                shortTemplate.set(shortTemplate + shortHybrid + shortLongDouble + tinyShortDouble)
                tinyTemplate.set(tinyTemplate + tinyHybrid + tinyShortDouble + 2 * product)
                longHybrid.set(0)
                shortHybrid.set(0)
                tinyHybrid.set(0)
                longLongDouble.set(0)
                shortLongDouble.set(0)
                tinyShortDouble.set(0)
                product.set(0)
            }
            heat
            let cool = Do(Step.cool, when: tee == "TooHot" && stage == "denatured") {
                tee.set("Hot")
                stage.set("ready")
            }
            cool
            let anneal = Do(Step.anneal, when: tee == "Hot" && stage == "ready") {
                With(IntRange(0, through: longTemplate), IntRange(0, through: shortTemplate),
                     IntRange(0, through: tinyTemplate)) { long, short, tiny in
                    let count = long + short + tiny
                    When(count >= 1 && count <= primer)
                    tee.set("Warm")
                    stage.set("annealed")
                    primer.set(primer - count)
                    longTemplate.set(longTemplate - long)
                    shortTemplate.set(shortTemplate - short)
                    tinyTemplate.set(tinyTemplate - tiny)
                    longHybrid.set(longHybrid + long)
                    shortHybrid.set(shortHybrid + short)
                    tinyHybrid.set(tinyHybrid + tiny)
                }
            }
            anneal
            let extend = Do(Step.extend, when: tee == "Warm" && stage == "annealed") {
                stage.set("extended")
                cycle += 1
                tee.set("Hot")
                shortLongDouble.set(shortLongDouble + longHybrid)
                tinyShortDouble.set(tinyShortDouble + shortHybrid)
                product.set(product + tinyHybrid)
                longHybrid.set(0)
                shortHybrid.set(0)
                tinyHybrid.set(0)
            }

            extend
            WeakFairness(anneal)
            WeakFairness(heat)
            WeakFairness(cool)
            WeakFairness(extend)

            let TypeOK = Invariant()
            TypeOK {
                Set<String>(["Warm", "Hot", "TooHot"]).contains(tee)
                primer >= 0 && cycle >= 0
                longTemplate >= 0 && shortTemplate >= 0 && tinyTemplate >= 0
                longHybrid >= 0 && shortHybrid >= 0 && tinyHybrid >= 0
                longLongDouble >= 0 && shortLongDouble >= 0 && tinyShortDouble >= 0 && product >= 0
                Set<String>(["init", "ready", "annealed", "extended", "denatured"]).contains(stage)
            }
            Invariant("thirdCycleProduct") { cycle >= 3 || product == 0 }
            let stagesInstance = Instance(of: GlowingStagesModel.self) {
                Bind(\.DNA, to: DNA)
                Bind(\.PRIMER, to: PRIMER)
            }
            stagesInstance
            let stagesSpec = Refinement(instance: stagesInstance) {
                Map(\.tee, projecting: tee)
                Map(\.primer, from: primer)
                Map(\.dna, from: doubles)
                Map(\.template, from: templates)
                Map(\.hybrid, from: hybrids)
                Map(\.stage, projecting: stage)
                Map(\.cycle, from: cycle)
            }
            stagesSpec
            let primerDepleted = Temporal()
            primerDepleted(.eventually(primer == 0))

            Validation("Upstream") {
                Bind(DNA, to: 5)
                Bind(PRIMER, to: 5)
            }.checkingDeadlock(false)
        }
    }
}
