@testable import SwiftTLAPlugin
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized)
struct SymmetryParserFidelityTests {
    @Test("Symmetry parses a finite-domain set")
    func parsesFiniteDomainSet() throws {
        let closure = try #require(Parser.parse(source: """
        {
            let TxId = Symmetry(Set(Transaction.all))
            TxId
        }
        """).statements.first?.item.as(ClosureExprSyntax.self))

        let parsed = SpecParser.parseSpecClosure(named: "Parsed",
            closure,
            sourceTypes: .init(enums: [
                .init(
                    typeName: "Transaction",
                    cases: [],
                    finiteValues: [.string("t1"), .string("t2")]
                )
            ])
        )

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.symmetrySets == [
            SymmetrySet(variableName: "TxId", values: [.string("t1"), .string("t2")])
        ])
    }

    @Test("Symmetry participates in generated parser-builder fidelity")
    func macroExpansionPreservesSymmetry() {
        #expect(GeneratedSymmetryModel.spec.symmetrySets == [
            SymmetrySet(variableName: "TxId", values: [.string("t1"), .string("t2")])
        ])
    }

    @Test("Configured symmetry retains the parameter through native compilation and TLA export")
    func parameterBoundSymmetry() throws {
        let specification = GeneratedParameterSymmetryModel.spec
        let parameter = try #require(specification.parameters.first)
        #expect(specification.symmetrySets.map(\.domain) == [.parameter(parameter.reference)])

        let scenarios = try GeneratedParameterSymmetryModel.validationScenarios()
        #expect(scenarios.count == 2)
        let exported = try scenarios.map {
            try GeneratedParameterSymmetryModel.render(configuration: $0.configuration).tlaBundle
        }
        #expect(exported[0].tla == exported[1].tla)
        #expect(exported[0].tla.contains("SymmmembersSymmetry == Permutations(members)"))
        #expect(exported.allSatisfy { !$0.cfg.contains("SYMMETRY") })
        #expect(exported[0].cfg.contains("CONSTANT members = {1, 2}"))
        #expect(exported[1].cfg.contains("CONSTANT members = {3, 4}"))
        for scenario in scenarios {
            let selected = try scenario.render()
            #expect(selected.tlaBundle.cfg.contains("SYMMETRY SymmmembersSymmetry"))
            #expect(try selected.plusCalBundle().tla.contains("SymmmembersSymmetry == Permutations(members)"))
        }
    }

    @Test("Symmetry requires a bound registration in #spec")
    func rejectsUnboundSymmetry() throws {
        let inline = try #require(Parser.parse(source: """
        {
            Symmetry(Set(Transaction.all))
        }
        """).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", inline,
            sourceTypes: .init(enums: [
                .init(typeName: "Transaction", cases: [],
                    finiteValues: [.string("t1"), .string("t2")])
            ]))
        #expect(parsed.diagnostics.map(\.message) == [
            "Symmetry requires an immutable named let binding and a registration reference."
        ])

        let mutable = try #require(Parser.parse(source: """
        {
            var TxId = Symmetry(Set(Transaction.all))
            TxId
        }
        """).statements.first?.item.as(ClosureExprSyntax.self))
        let mutableParsed = SpecParser.parseSpecClosure(named: "Parsed", mutable,
            sourceTypes: .init(enums: [
                .init(typeName: "Transaction", cases: [],
                    finiteValues: [.string("t1"), .string("t2")])
            ]))
        #expect(mutableParsed.diagnostics.map(\.message).contains(
            "Symmetry requires a unique immutable let binding."))
    }

    @Test("Scenario symmetry selection requires a registered local handle")
    func rejectsForeignScenarioSymmetry() throws {
        let closure = try #require(Parser.parse(source: """
        {
            let check = Validation {}.usingSymmetry(other)
            check
        }
        """).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
        #expect(parsed.diagnostics.map(\.message).contains(
            "Symmetry selection requires a registered model-owned symmetry binding."))
    }
}

@TLAModel
private struct GeneratedSymmetryModel {
    enum Transaction: String, FiniteTLAValueDomain {
        case t1, t2

        static var defaultValue: Self { .t1 }
        static let finiteValues: [Self] = [.t1, .t2]
    }

    static var spec: TLASpec {
        #spec("GeneratedSymmetry") { scope in
            let value = scope.sharedVar(_name: "value", initial: 0)
            let TxId = Symmetry(Set(Transaction.all))
            TxId
            Invariant("TypeOK") { value >= 0 }
        }
    }
}

@TLAModel
private struct GeneratedParameterSymmetryModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec("GeneratedParameterSymmetry") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: NonEmptySubsets(of: Set<Int>([1, 2, 3, 4])))
            let value = scope.sharedVar(initial: 0)
            let membersSymmetry = Symmetry(members)
            membersSymmetry
            let algorithm = Algorithm(label: "Stay") {
                Do(Step.stay) { Assign(value, to: value) }
            }
            algorithm
            Invariant("TypeOK") { value >= 0 }
            let first = Validation { Bind(members, to: Set<Int>([1, 2])) }
                .usingSymmetry(membersSymmetry)
            first
            let second = Validation { Bind(members, to: Set<Int>([3, 4])) }
                .usingSymmetry(membersSymmetry)
            second
        }
    }
}
