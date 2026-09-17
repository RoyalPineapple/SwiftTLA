import Foundation
import Testing
import UpstreamParity
@testable import SwiftTLA

struct TemporalObligationRenderingTests {
    @Test("configured property binders serialize each member without free names or mutable domains")
    func instantiatesBindings() throws {
        let rendered = try RecurringPopulation.render(configuration: .init(members: [0, 1]))
        let obligations = try #require(rendered.temporalObligations["EachProgress"])
        #expect(obligations.count == 4)
        for member in [0, 1] {
            let prefix = "LET _process == \(member) IN "
            #expect(obligations.filter { $0.initialCondition.hasPrefix(prefix) && $0.property.hasPrefix(prefix) }.count == 2)
        }
        #expect(try rendered.temporalObligationBundles(checking: "EachProgress")?.count == 4)
        let empty = try RecurringPopulation.render(configuration: .init(members: []))
        #expect(try empty.temporalObligationBundles(checking: "EachProgress") == nil)
        #expect(empty.tlaBundle.cfg.contains("PROPERTY EachProgress"))
    }

    @Test("conditional action claims partition initial states without changing transitions or fairness")
    func partitionsInitialStates() throws {
        let rendered = try TransitionPropertyClaims.render(configuration: .init(limit: 2))
        let original = rendered.tlaBundle
        let bundles = try #require(try rendered.temporalObligationBundles(checking: "composed"))
        #expect(bundles.count == 3)
        #expect(bundles.allSatisfy { $0.tla.contains("__SwiftTLAObligationBehavior == Spec /\\ ((IF") })
        #expect(bundles.allSatisfy { $0.cfg.contains("SPECIFICATION __SwiftTLAObligationBehavior") })
        #expect(bundles.allSatisfy { $0.cfg.contains("CONSTANT limit = 2") })
        #expect(bundles.allSatisfy { !$0.cfg.contains("SYMMETRY") && $0.cfg.contains("CHECK_DEADLOCK FALSE") })
        let originalDefinitions = String(try #require(original.tla.components(separatedBy: "====").first))
        #expect(bundles.allSatisfy { $0.tla.hasPrefix(originalDefinitions) })
        #expect(bundles.contains { $0.tla.contains("__SwiftTLAObligationProperty == [][") })
        #expect(bundles.filter { $0.tla.contains("__SwiftTLAObligationProperty == <>") }.count == 2)
        #expect(rendered.tlaBundle == original)
        #expect(try rendered.temporalObligationBundles(checking: "increases") == nil)
    }

    @Test("nested branch guards stay lazy and check selection retains the chosen behavior")
    func preservesNestedGuardsAndBehavior() throws {
        let scenario = try #require(try ConditionalTemporalClaims.validationScenarios().first)
        let rendered = try scenario.render()
        let original = try #require(rendered.temporalObligations["startsHere"])
        #expect(original.contains { $0.initialCondition.contains("THEN FALSE ELSE (IF") })
        let selected = try rendered.selectingChecks(ModelChecks(properties: ["startsHere"], checkDeadlock: false),
            formalPropertyNames: ["startsHere": "startsHere"], behavior: .initialAndNext)
        let bundles = try #require(try selected.temporalObligationBundles(checking: "startsHere"))
        #expect(bundles.allSatisfy { $0.tla.contains("__SwiftTLAObligationBehavior == Init /\\") })
        #expect(bundles.allSatisfy { $0.cfg.contains("INIT __SwiftTLAObligationBehavior\nNEXT Next") })
        #expect(throws: CompilationDiagnostic.self) {
            try selected.temporalObligationBundles(checking: "missesOtherInitial")
        }
    }
}
