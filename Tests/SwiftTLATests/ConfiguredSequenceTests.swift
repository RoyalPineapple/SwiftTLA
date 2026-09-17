import Testing
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ConfiguredSequenceTests {
    @Test("configured sequence domains preserve every length, order, and index convention")
    func completeConfiguredDomains() throws {
        for scenario in try ConfiguredSequenceDomainMachine.validationScenarios() {
            let members = scenario.configuration.members
            let rows = Set([[]] + members.map { [$0] } + members.flatMap { a in members.map { [a, $0] } })
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
            #expect(try scenario.render().tlaBundle.tla.contains("\\in members"))
        }
    }

    @Test("sequence elements retain nominal enum types through generated initial states")
    func preservesNominalElements() throws {
        let scenario = try #require(NominalSequenceMachine.validationScenarios().first)
        let rows: Set<[NominalSequenceMachine.Choice]> = Set(try scenario.initialMachines().map { $0.state.row })
        #expect(rows == [[], [.one], [.two], [.one, .one], [.one, .two], [.two, .one], [.two, .two]])
    }

    @Test("sequence construction retains symbolic reads without capturing source variables")
    func preservesSymbolicDomain() throws {
        let source = StateExpr.variable("__sequenceMember0")
        let domain = Sequences(of: Expr<Set<Int>>(source), lengths: 2...2).stateExpr
        #expect(domain.freeVariableNames == ["__sequenceMember0"])
        let parser = ParserSession()
        let scope = ParserSession.TypedFacadeScope.empty.extending(binding: "members",
            to: source, shape: .set(.int))
        let syntax: ExprSyntax = "Sequences(of: members, lengths: 2...2)"
        #expect(parser.decodeTypedFacadeValue(syntax, scope: scope) == domain)
    }
}
