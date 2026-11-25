import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct GlowingCleanModel: Sendable {
    private enum Step: String, CaseIterable { case heat, cool, anneal, extend }

    package static var spec: TLASpec {
        #spec("clean") { scope in
            Extends(.naturals)
            let DNA = scope.parameter(as: Int.self, in: 5...5)
            let PRIMER = scope.parameter(as: Int.self, in: 5...5)
            let tee = scope.sharedVar(initial: "Hot")
            let primer = scope.sharedVar(initial: PRIMER)
            let dna = scope.sharedVar(initial: DNA)
            let template = scope.sharedVar(initial: 0)
            let hybrid = scope.sharedVar(initial: 0)
            let total = template + primer + 2 * (dna + hybrid)

            Do(Step.heat, when: tee == "Hot") {
                tee.set("TooHot")
                primer.set(primer + hybrid)
                template.set(template + hybrid + 2 * dna)
                dna.set(0)
                hybrid.set(0)
            }
            Do(Step.cool, when: tee == "TooHot") { tee.set("Hot") }
            Do(Step.anneal, when: tee == "Hot") {
                With(IntRange(1, through: If(primer < template, then: primer, else: template))) { k in
                    tee.set("Warm")
                    primer.set(primer - k)
                    template.set(template - k)
                    hybrid.set(hybrid + k)
                }
            }
            Do(Step.extend, when: tee == "Warm") {
                tee.set("Hot")
                dna.set(dna + hybrid)
                hybrid.set(0)
            }

            let TypeOK = Invariant()
            TypeOK {
                Set<String>(["Warm", "Hot", "TooHot"]).contains(tee)
                primer >= 0 && dna >= 0 && template >= 0 && hybrid >= 0
            }
            let primerPositive = Invariant()
            primerPositive { primer >= 0 }
            let preservationInvariant = Invariant()
            preservationInvariant { total == PRIMER + 2 * DNA }
            let preservationProperty = Temporal()
            preservationProperty(.alwaysStep(on: total) { before, after in before == after })

            Validation("Upstream") {
                Bind(DNA, to: 5)
                Bind(PRIMER, to: 5)
            }
            Validation("APclean") {
                Bind(DNA, to: 5)
                Bind(PRIMER, to: 5)
            }
                .checking(only: [TypeOK, primerPositive, preservationInvariant])
        }
    }
}
