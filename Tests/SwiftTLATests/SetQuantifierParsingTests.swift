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

    @Test("quantified predicates retain immutable lexical expressions", arguments: [
        "ForAll(in: Set<Int>([1, 2])) { member in let next = member + 1; let increasing = next > member; return increasing }",
        "Exists(in: Set<Int>([1, 2])) { member in let doubled = member * 2; return doubled == 4 }",
        "ForAll(in: Set<Int>([1, 2])) { member in let candidates = Set<Int>([1, 2]); return Exists(in: candidates) { other in let matches = member == other; return matches } }",
        "ForAll(in: Set<Int>([])) { member in let invalid = member / 0; return invalid == 0 }",
        "ForAll(in: Set<Int>([1])) { member in let outer = member; return Exists(in: Set<Int>([2])) { member in outer < member } }",
        "ForAll(in: Set<Int>([1]), and: Set<Int>([2])) { left, right in let sum = left + right; return sum == 3 }"
    ])
    func preservesLexicalPredicates(_ source: String) throws {
        let expression = try #require(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)))
        #expect(try compiledValue(expression) == .bool(true))
    }

    @Test("quantifiers reject malformed predicate bodies", arguments: [
        "ForAll(in: Set<Int>([1])) { member in var value = member; return value == 1 }",
        "ForAll(in: Set<Int>([1])) { member in let value = member; value == 1 }",
        "ForAll(in: Set<Int>([1])) { member in return true; return false }",
        "ForAll(in: Set<Int>([1])) { member in let value = unknown(member); return true }",
        "ForAll(in: Set<Int>([1])) { member in let value = member }"
    ])
    func rejectsMalformedPredicates(_ source: String) throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)) == nil)
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
