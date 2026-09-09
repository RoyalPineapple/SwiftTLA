import Testing
@testable import SwiftTLA

@Suite struct TypedArithmeticResultTests {
    @Test("Division and modulo preserve the integer expression type for literal and expression operands")
    func integerResults() throws {
        let results: [Expr<Int>] = [
            Expr<Int>(8) / 2,
            Expr<Int>(8) / Expr<Int>(2),
            Expr<Int>(8) % 3,
            Expr<Int>(8) % Expr<Int>(3)
        ]
        let values = try results.map { try compiledValue($0.stateExpr) }
        #expect(values == [.int(4), .int(4), .int(2), .int(2)])
    }
}
