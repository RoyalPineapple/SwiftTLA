import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SetQuantifierParsingTests {
    @Test("two-domain quantifiers preserve named, implicit, and unused binders", arguments: [
        "ForAll(in: Set<Int>([1, 2]), and: Set<Int>([3, 4])) { left, right in left < right }",
        "SwiftTLA.ForAll(in: Set<Int>([1, 2]), and: Set<Int>([3, 4])) { $0 < $1 }",
        "Exists(in: Set<Int>([1, 2]), and: Set<Int>([3, 4])) { left, right in left + right == 6 }",
        "ForAll(in: Set<Int>([]), and: Set<Int>([1])) { _, _ in false }",
        "!Exists(in: Set<Int>([1]), and: Set<Int>([])) { _, _ in true }"
    ])
    func preservesQuantifiedMeaning(_ source: String) throws {
        let expression = try #require(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)))
        #expect(try compiledValue(expression) == .bool(true))
    }

    @Test("quantifiers reject malformed domain labels and binder counts", arguments: [
        "ForAll(in: Set<Int>([1]), and: Set<Int>([2])) { only in true }",
        "Exists(in: Set<Int>([1])) { first, second in true }",
        "ForAll(in: Set<Int>([1]), and: Set<Int>([2])) { same, same in true }",
        "ForAll(in: Set<Int>([1]), other: Set<Int>([2])) { first, second in true }"
    ])
    func rejectsMalformedQuantifiers(_ source: String) throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)) == nil)
    }
}
