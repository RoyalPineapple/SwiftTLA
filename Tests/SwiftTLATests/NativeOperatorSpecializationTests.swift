@testable import SwiftTLAPlugin
import Testing
@testable import SwiftTLA

@Suite struct NativeOperatorSpecializationTests {
    @Test("filter and CHOOSE retain nominal evidence established by their predicates")
    func selectionResultKeepsPredicateEvidence() throws {
        let domain = StateExpr.setLiteral([.value(.string("read"))])
        let predicate = StateExpr.equal(.variable("candidate"), .variable("selected"))
        let filter = StateExpr.setFilter(domain, "candidate", predicate)
        let choice = StateExpr.choose(domain, "candidate", predicate)
        let compilation = try TLASpec(
            name: "SelectionResultEvidence",
            variables: [.init(name: "selected", initialization: .value(.string("read")), generatedSwiftType: "Kind", origin: .compiler)],
            actions: [],
            invariants: [
                .init(name: "Filter", body: .equal(.cardinality(filter), .int(1))),
                .init(name: "Choice", body: .equal(.cardinality(.setLiteral([choice])), .int(1))),
            ]
        ).compile()

        let inference = try NativeTypeInference(compilation: compilation, sourceTypes: .init(enums: ["Kind": [.string("read")]]))
        guard case .equal(.cardinality(let filtered), _) = compilation.semantics.invariants[0].body,
              case .equal(.cardinality(.setLiteral(let choices)), _) = compilation.semantics.invariants[1].body else {
            Issue.record("Expected selection fixture expressions")
            return
        }
        let selected = try #require(choices.first)
        #expect(try inference.type(of: filtered, expected: .set(.string)) == .set(.named("Kind")))
        #expect(try inference.type(of: selected, expected: .string) == .named("Kind"))
    }

}
