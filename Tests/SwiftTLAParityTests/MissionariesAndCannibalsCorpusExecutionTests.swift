import Foundation
import Testing
import SwiftTLA
@testable import UpstreamParity

struct MissionariesAndCannibalsCorpusExecutionTests {
    @Test("both published configurations resolve to pinned independent inputs")
    func pinnedConfigurations() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        let declarations = manifest.cases.filter { $0.sourceModel.rawValue == "missionaries-and-cannibals" }
        #expect(Set(declarations.map(\.scenario)) == ["MissionariesAndCannibals", "APMissionariesAndCannibals"])
        for declaration in declarations {
            #expect(try declaration.resolveScenario()?.name == declaration.scenario)
            let module = try Data(contentsOf: projectURL("Verification/FiniteGraph/fixtures/" + declaration.module))
            let configuration = try Data(contentsOf: projectURL(
                "Verification/FiniteGraph/fixtures/" + declaration.configuration))
            #expect(SHA256.hex(module) == declaration.moduleSHA256)
            #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
            #expect(declaration.comparisonMode == .decisiveCounterexample)
        }
    }

    @Test("a crossing moves one or two people and leaves both banks safe")
    func crossingRelation() throws {
        for scenario in try MissionariesAndCannibalsModel.validationScenarios() {
            let initial = try #require(scenario.initialMachines().first)
            let people: Set<MissionariesAndCannibalsModel.Person> = scenario.name == "MissionariesAndCannibals"
                ? [.m1, .m2, .m3, .c1, .c2, .c3]
                : [.apM1, .apM2, .apM3, .apC1, .apC2, .apC3]
            #expect(initial.state.bank_of_boat == .E)
            #expect(initial.state.who_is_on_bank[.E] == people)
            #expect(initial.state.who_is_on_bank[.W] == [])
            let sample = try #require(people.first)
            #expect(sample.tlaValue == (scenario.name == "MissionariesAndCannibals"
                ? .constant(sample.rawValue) : .string(sample.rawValue)))
            let successors = try initial.successors()
            #expect(!successors.isEmpty)
            for (_, successor) in successors {
                let east = try #require(successor.state.who_is_on_bank[.E])
                let west = try #require(successor.state.who_is_on_bank[.W])
                #expect(successor.state.bank_of_boat == .W)
                #expect((1...2).contains(west.count))
                #expect(east.isDisjoint(with: west))
                #expect(east.union(west) == people)
                for bank in [east, west] {
                    let missionaries = bank.filter { $0.rawValue.hasPrefix("m") }.count
                    let cannibals = bank.count - missionaries
                    #expect(missionaries == 0 || cannibals <= missionaries)
                }
            }
        }
    }

    @Test("the model selects the published deliberate solution violation")
    func solutionSelection() throws {
        let scenarios = try MissionariesAndCannibalsModel.validationScenarios()
        #expect(scenarios.map(\.name) == ["MissionariesAndCannibals", "APMissionariesAndCannibals"])
        for scenario in scenarios {
            let rendered = try scenario.render()
            #expect(rendered.checkNames == ["TypeOK", "Solution"])
            #expect(rendered.checksDeadlock)
            #expect(scenario.checkingMode == .decisiveCounterexample)
            if scenario.name == "APMissionariesAndCannibals" {
                #expect(rendered.tlaBundle.cfg.contains("\"m1_OF_PERSON\""))
                #expect(rendered.tlaBundle.cfg.contains("\"c1_OF_PERSON\""))
            } else {
                #expect(rendered.tlaBundle.cfg.contains("m1"))
                #expect(!rendered.tlaBundle.cfg.contains("\"m1_OF_PERSON\""))
            }
            let run = try NativeScenarioRun(scenario, maximumStates: 1_000)
            try run.validateExpectations()
            guard case .violated = run.native.checks.properties["Solution"] else {
                Issue.record("Expected the published solution counterexample")
                continue
            }
            #expect(run.native.graph == nil)
        }
    }
}
