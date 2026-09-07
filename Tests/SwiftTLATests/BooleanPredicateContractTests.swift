@testable import SwiftTLA
import Testing

@Suite struct BooleanPredicateContractTests {
    @Test("quantifiers and filters reject non-Boolean predicate results")
    func rejectsNonBooleanPredicates() {
        let domain = StateExpr.setLiteral([.int(1)])
        let expressions: [StateExpr] = [
            .setFilter(domain, "item", .variable("item")),
            .forAll(domain, "item", .variable("item")),
            .exists(domain, "item", .variable("item")),
            .choose(domain, "item", .variable("item"))
        ]
        for expression in expressions {
            #expect(throws: EvalError.expected(.boolean, actual: [.integer(1)])) {
                try compiledValue(expression)
            }
        }
    }

    @Test("valid bound Boolean predicates keep their truth values")
    func validBoundPredicates() throws {
        let domain = StateExpr.setLiteral([.bool(false), .bool(true)])
        #expect(try compiledValue(.setFilter(domain, "item", .variable("item"))) == .set([.bool(true)]))
        #expect(try compiledValue(.forAll(domain, "item", .variable("item"))) == .bool(false))
        #expect(try compiledValue(.exists(domain, "item", .variable("item"))) == .bool(true))
        #expect(try compiledValue(.choose(domain, "item", .variable("item"))) == .bool(true))
    }

    @Test("empty domains do not evaluate predicate bodies")
    func emptyDomains() throws {
        let domain = StateExpr.setLiteral([])
        #expect(try compiledValue(.setFilter(domain, "item", .int(1))) == .set([]))
        #expect(try compiledValue(.forAll(domain, "item", .int(1))) == .bool(true))
        #expect(try compiledValue(.exists(domain, "item", .int(1))) == .bool(false))
    }
}
