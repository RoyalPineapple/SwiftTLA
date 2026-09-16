import Testing
import UpstreamParity
@testable import SwiftTLA

struct PropertyDeclarationNamesTests {
    @Test("qualified property constructors share Swift names across built and generated models")
    func preservesQualifiedBindingNames() throws {
        let scenario = try #require(try QualifiedPropertyClaims.validationScenarios().first)
        #expect(scenario.checking.properties == [.safe, .reachable, .always, .eventually, .recurring, .stable, .response])
        let run = try NativeScenarioRun(scenario, maximumStates: 4)
        try run.validateExpectations()
        let rendered = try scenario.render()
        let cfg = try #require(rendered.tlaBundle.root.cfg)
        #expect(cfg.contains("INVARIANT safe"))
        #expect(cfg.contains("PROPERTY response"))
        #expect(try rendered.plusCalBundle().root.cfg == cfg)
        #expect(try QualifiedPropertyClaims.spec.compile().identity == QualifiedPropertyClaims.spec.compile().identity)
    }
}
