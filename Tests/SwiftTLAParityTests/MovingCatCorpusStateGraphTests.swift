import SwiftTLA
import Testing
import UpstreamParity

struct MovingCatCorpusStateGraphTests {
    @Test("all published box counts select the complete generated graph and checks")
    func preservesConfiguredGraphsAndChecks() throws {
        let scenarios = try CatModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["CatEvenBoxes", "CatOddBoxes", "APCat"])
        #expect(scenarios.map { $0.configuration.Number_Of_Boxes } == [6, 5, 4])
        for (scenario, counts) in zip(scenarios, [(48, 80), (30, 48), (16, 24)]) {
            let run = try NativeScenarioRun(scenario, maximumStates: 100)
            try run.validateExpectations()
            #expect(run.coverage.selectedProperties == (scenario.name == "APCat"
                ? ["TypeOK"] : ["TypeOK", "Victory"]))
            let graph = try #require(run.native.graph).graph
            #expect(graph.initialStateKeys.count == counts.0)
            #expect(graph.states.count == counts.0)
            #expect(graph.edges.count == counts.1)
            #expect(run.native.checks.deadlock == .satisfied)
            #expect(run.native.checks.properties["TypeOK"] == .satisfied)
            #expect(run.native.checks.properties["Victory"] == (scenario.name == "APCat" ? nil : .satisfied))
            let rendered = try scenario.render()
            #expect(rendered.tlaBundle.cfg.contains("CONSTANT Number_Of_Boxes = \(scenario.configuration.Number_Of_Boxes)"))
            #expect(rendered.checkNames == (scenario.name == "APCat" ? ["TypeOK"] : ["TypeOK", "Victory"]))
            #expect(rendered.actions.map(\.sourceName) == ["Next"])
            #expect(rendered.tlaBundle.tla.contains("WF_(cat_box)(Next)"))
        }
    }
}
