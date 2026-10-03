import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct SetClosureParsingTests {
    @Test("collection closures preserve shorthand, unused arguments, and nested scopes", arguments: [
        "Set<Int>([1, 2]).mapping { $0 * 2 }.filtering { $0 == 4 }",
        "Set<Int>([1, 2]).mapping { _ in 4 }",
        "Set<Int>([1, 2]).flatMapping { _ in Set<Int>([4]) }",
        "Set<Int>([1, 2]).flatMapping { Set<Int>([4]).mapping { $0 } }",
        "Set<Int>([1, 2]).flatMapping { outer in Set<Int>([1, 2]).mapping { outer + $0 } }.filtering { $0 == 4 }",
        "Set<Int>([1, 2]).flatMapping { IntRange($0, through: $0).mapping { $0 * 2 } }.filtering { $0 == 4 }"
    ])
    func preservesClosureMeaning(_ source: String) throws {
        let expression = try #require(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)))
        #expect(try compiledValue(expression) == .set([.int(4)]))
    }

    @Test("collection closures reject ignored arguments and invalid arity", arguments: [
        "Set<Int>([1]).mapping { first, second in first }",
        "Set<Int>([1]).filtering { () in true }",
        "Set<Int>([1]).mapping(999) { member in member }",
        "Set<Int>([1]).flatMapping { member in Set<Int>([member]) } extra: { 0 }"
    ])
    func rejectsMalformedClosures(_ source: String) throws {
        #expect(SpecParser.decodeStateExpr(try parseSpecTestExpression(source)) == nil)
    }
}
