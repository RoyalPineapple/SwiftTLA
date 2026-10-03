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
    func macroExpansionPreservesSymmetry() throws {
        #expect(GeneratedSymmetryModel.spec.symmetrySets == [
            SymmetrySet(variableName: "TxId", values: [.string("t1"), .string("t2")])
        ])
        let compilation = try GeneratedSymmetryModel.spec.compile()
        #expect(compilation.semantics.symmetrySets.map(\.values) == [
            [.string("t1"), .string("t2")]
        ])
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
