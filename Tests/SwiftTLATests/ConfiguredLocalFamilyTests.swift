import Testing
@testable import SwiftTLA

struct ConfiguredLocalFamilyTests {
    @Test("configured local families retain sparse and empty integer domains")
    func configuredDomains() throws {
        for scenario in try ConfiguredLocalFamilyModel.validationScenarios() {
            let members = scenario.configuration.members
            var machine = try #require(scenario.initialMachines().first)
            #expect(ConfiguredLocalFamilyModel.Property.allCases == [.Family])
            #expect(try machine.violatedInvariants().isEmpty)
            for action in try machine.enabledActions() {
                _ = try machine.send(action)
                #expect(try machine.violatedInvariants().isEmpty)
            }
            let graph = try scenario.explore(maximumStates: 10)
            #expect(graph.transitions.count == 1 << members.count)
            #expect(graph.safetyViolations.isEmpty)
            let rendered = try scenario.render()
            #expect(rendered.tlaBundle.tla.contains("DOMAIN value"))
            #expect(try rendered.plusCalBundle().tla.contains("DOMAIN value"))
        }
    }

    @Test("local family and range views use ordinary typed dictionaries and sets")
    func ordinaryCollections() {
        let local = ProcessScope().localVar(_name: "value", initial: 0)
        let family: Expr<[Int: Int]> = local.family(for: Int.self)
        let _: Expr<Set<Int>> = Range(family)
        #expect(family.raw == .processLocalFamily("value"))
    }
}
