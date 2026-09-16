import Testing
import UpstreamParity
@testable import SwiftTLA

struct TemporalPopulationTests {
    @Test("configured temporal members recur independently in generated native checking")
    func checksEachMember() throws {
        for scenario in try RecurringPopulation.validationScenarios() {
            let graph = try scenario.explore(maximumStates: 20)
            #expect(graph.temporalResults[.EachRecurs]?.status ==
                (scenario.configuration.members.contains(2) ? .violated : .satisfied))
            #expect(graph.temporalResults[.EachVisits]?.status == .satisfied)
            let tla = try scenario.render().tlaBundle.tla
            #expect(tla.contains("EachRecurs == (\\A _process \\in members: []<>(value = _process))"))
            #expect(tla.contains("EachVisits == (\\A _process \\in members: <>visited[_process])"))
        }
    }

    @Test("a failing member retains a native lasso for the quantified claim")
    func retainsCounterexample() throws {
        let machine = try RecurringPopulation.makeMachine(configuration: .init(members: [2]))
        let graph = try ReachabilityGraph(initialMachines: [machine], maximumStates: 20)
        let result = try #require(graph.temporalResults[.EachRecurs])
        #expect(result.status == .violated)
        #expect(result.reason == .violatingFairLasso)
        let trace = try #require(result.witness)
        #expect(trace.cycle.first == trace.cycle.last)
        #expect(trace.cycleActions.contains(.toggle(process: 2)))
        #expect(graph.temporalResults[.EachVisits]?.status == .satisfied)
    }

    @Test("authored PlusCal exports the same quantified temporal properties")
    func exportsAuthoredProperties() throws {
        for scenario in try RecurringPopulation.validationScenarios() {
            let rendered = try scenario.render()
            let plusCal = try rendered.plusCalBundle()
            #expect(plusCal.root.cfg == rendered.tlaBundle.cfg)
            #expect(plusCal.root.tla.contains("CONSTANTS members"))
            for definition in [
                "EachRecurs == (\\A _process \\in members: []<>(value = _process))",
                "EachVisits == (\\A _process \\in members: <>visited[_process])"
            ] {
                #expect(rendered.tlaBundle.tla.contains(definition))
                #expect(plusCal.root.tla.components(separatedBy: definition).count == 2)
            }
        }
    }

    @Test("formal temporal checking binds complete dependent domains and handles empty populations")
    func checksFormalDomains() throws {
        for members in [[], [0, 1], [0, 1, 2]] as [[Int]] {
            var spec = canonicalTestSpec(variables: [("value", .value(.int(0)))], actions: [
                ("toggle", .assign(.named("value"), .subtract(.int(1), .variable("value"))), [])
            ])
            spec.fairness = [.weakFairness("toggle")]
            spec.temporalProperties = [.init(name: "Each", expr: .alwaysEventually(.equal(.variable("value"), .variable("copy"))),
                bindings: [
                    ActionBinding(name: "member", values: members.map(TLAValue.int), generatedSwiftType: "Int"),
                    ActionBinding(name: "copy", domain: .setLiteral([.variable("member")]), generatedSwiftType: "Int")
                ])]
            let compilation = try spec.compile()
            let exploration = try ModelChecker(compilation: compilation,
                configuration: FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)).explore()
            let result = try #require(exploration.analyzeTemporalProperties(in: compilation).first)
            #expect(result.status == (members.contains(2) ? .violated : .satisfied))
            if members.contains(2) { #expect(result.witness != nil) }
        }
    }

    @Test("temporal specialization preserves binder scope and all predicate references")
    func specializesQuantifier() {
        let property = NamedTemporal(name: "Each", expr: .leadsTo(.variable("target"), .variable("member")),
            bindings: [ActionBinding(name: "member", domain: .variable("population"), generatedSwiftType: "Bool")])
        let specialized = property.substitutingVariables(["population": .setLiteral([.value(.bool(true))]),
            "target": .variable("member")])
        #expect(specialized.bindings[0].name == "member_1")
        #expect(specialized.bindings[0].domain == .setLiteral([.value(.bool(true))]))
        #expect(specialized.expr == .leadsTo(.variable("member"), .variable("member_1")))
    }

    @Test("temporal populations cannot depend on state")
    func rejectsMutablePopulation() {
        var spec = canonicalTestSpec(variables: [("value", .value(.int(0)))], actions: [])
        spec.temporalProperties = [.init(name: "Each", expr: .eventually(.value(.bool(true))), bindings: [
            ActionBinding(name: "member", domain: .integerRange(.int(0), .variable("value")), generatedSwiftType: "Int")
        ])]
        #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
    }
}
