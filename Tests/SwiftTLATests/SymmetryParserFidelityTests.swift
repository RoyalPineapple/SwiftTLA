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
            Symmetry("TxId", Set(Transaction.all))
        }
        """).statements.first?.item.as(ClosureExprSyntax.self))

        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [
                .init(
                    typeName: "Transaction",
                    cases: .init([]),
                    finiteValues: [.string("t1"), .string("t2")]
                )
            ]
        )

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.symmetrySets == [
            SymmetrySet(variableName: "TxId", values: [.string("t1"), .string("t2")])
        ])
    }

    @Test("Symmetry participates in generated parser-builder fidelity")
    func generatedModelPreservesSymmetry() throws {
        #expect(GeneratedSymmetryModel.spec.symmetrySets == [
            SymmetrySet(variableName: "TxId", values: [.string("t1"), .string("t2")])
        ])
        let compilation = try GeneratedSymmetryModel.spec.compile()
        #expect(compilation.semantics.symmetrySets.map(\.values) == [
            [.string("t1"), .string("t2")]
        ])
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
            let value = scope.sharedVar("value", initial: 0)
            Symmetry("TxId", Set(Transaction.all))
            Invariant("TypeOK") { value >= 0 }
        }
    }
}
