import Testing
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ConfiguredSequenceTests {
    @Test("Algorithm lexical aliases retain configured sequence expressions")
    func algorithmBindings() throws {
        let scenarios = try ConfiguredAlgorithmBindingMachine.validationScenarios()
        #expect(scenarios.count == 2)
        for scenario in scenarios {
            let machine = try #require(scenario.initialMachines().first)
            let successors = try machine.successors(for: .adopt)
            let expected = Set((1...scenario.configuration.limit).map { Array(repeating: 7, count: $0) })
            #expect(Set(successors.map { $0.state.row }) == expected)
            let graph = try scenario.explore(maximumStates: 10)
            #expect(graph.safetyViolations.isEmpty)
            #expect(Set(graph.transitions.keys.map { $0.state.row }) == expected.union([[]]))
            #expect(try scenario.render().tlaBundle.tla == scenarios[0].render().tlaBundle.tla)
        }
    }

    @Test("configured sequence domains preserve every length, order, and index convention")
    func completeConfiguredDomains() throws {
        for scenario in try ConfiguredSequenceDomainMachine.validationScenarios() {
            let members = scenario.configuration.members
            let rows = Set(([[]] + members.map { [$0] } + members.flatMap { a in members.map { [a, $0] } })
                .filter { scenario.configuration.lengths.contains($0.count) })
            let sorted = rows.filter { $0 == $0.sorted() }
            let zeroBased = Set(rows.map { Dictionary(uniqueKeysWithValues: $0.enumerated().map { ($0.offset, $0.element) }) })
            let machines = try scenario.initialMachines()
            #expect(machines.count == rows.count * sorted.count * zeroBased.count)
            #expect(Set(machines.map { $0.state.row }) == rows)
            #expect(Set(machines.map { $0.state.sorted }) == sorted)
            #expect(Set(machines.map { $0.state.zeroBased }) == zeroBased)
            let graph = try scenario.explore(maximumStates: 500)
            #expect(graph.initialStates == Set(machines.map(\.snapshot)))
            #expect(graph.transitions.count == machines.count)
            #expect(graph.transitions.allSatisfy { source, edges in
                edges.count == 1 && edges[0].target == source && edges[0].action == .stay
            })
            #expect(graph.safetyViolations.isEmpty)
            #expect(try scenario.render().tlaBundle.tla.contains(" -> members]"))
        }
    }

    @Test("sequence elements retain nominal enum types through generated initial states")
    func preservesNominalElements() throws {
        let scenario = try #require(NominalSequenceMachine.validationScenarios().first)
        let rows: Set<[NominalSequenceMachine.Choice]> = Set(try scenario.initialMachines().map { $0.state.row })
        #expect(rows == [[], [.one], [.two], [.one, .one], [.one, .two], [.two, .one], [.two, .two]])
        for limit in 0...2 {
            let configuration = try NominalSequenceMachine.Configuration(members: [.one, .two], limit: limit)
            let initial = try NominalSequenceMachine.initialMachines(configuration: configuration)
            #expect(Set(initial.map { $0.state.row }) == rows.filter { $0.count <= limit })
            #expect(try NominalSequenceMachine.render(configuration: configuration).tlaBundle.tla
                == scenario.render().tlaBundle.tla)
        }
    }

    @Test("empty length domains stay empty and negative lengths fail rather than becoming empty sequences")
    func validatesLengths() throws {
        for (members, lengths): (Set<Int>, Set<Int>) in [([1, 2], []), ([], [1, 2])] {
            let configuration = try ConfiguredSequenceDomainMachine.Configuration(members: members, lengths: lengths)
            #expect(try ConfiguredSequenceDomainMachine.initialMachines(configuration: configuration).isEmpty)
            #expect(throws: GeneratedMachineError.noInitialState) {
                try ConfiguredSequenceDomainMachine.makeMachine(configuration: configuration)
            }
        }
        let invalid = try ConfiguredSequenceDomainMachine.Configuration(members: [1, 2], lengths: [-1, 0])
        #expect(throws: NativeMachineEvaluationError.noMatchingCase) {
            try ConfiguredSequenceDomainMachine.initialMachines(configuration: invalid)
        }
    }

    @Test("sequence construction retains symbolic reads without capturing source variables")
    func preservesSymbolicDomain() throws {
        let source = StateExpr.variable("__sequenceLength")
        let domain = Sequences(of: Expr<Set<Int>>(source), lengths: 2...2).stateExpr
        #expect(domain.freeVariableNames == ["__sequenceLength"])
        let parser = ParserSession()
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "members",
            to: source, shape: .set(.int))
        let syntax: ExprSyntax = "Sequences(of: members, lengths: 2...2)"
        #expect(parser.decodeTypedFacadeValue(syntax, scope: scope) == domain)
    }
}
