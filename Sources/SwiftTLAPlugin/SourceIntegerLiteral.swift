import SwiftSyntax

/// Decodes Swift integer source literals at the macro/parser boundary.
package enum SourceIntegerLiteral {
    package static func value(_ expression: some ExprSyntaxProtocol) -> Int? {
        let literal: IntegerLiteralExprSyntax
        let negative: Bool
        if let prefix = expression.as(PrefixOperatorExprSyntax.self),
           prefix.operator.text == "-",
           let operand = prefix.expression.as(IntegerLiteralExprSyntax.self) {
            literal = operand
            negative = true
        } else if let operand = expression.as(IntegerLiteralExprSyntax.self) {
            literal = operand
            negative = false
        } else { return nil }

        let source = literal.literal.text.filter { $0 != "_" }
        let radix: Int
        let digits: Substring
        switch source.prefix(2) {
        case "0b": radix = 2; digits = source.dropFirst(2)
        case "0o": radix = 8; digits = source.dropFirst(2)
        case "0x": radix = 16; digits = source.dropFirst(2)
        default: radix = 10; digits = source[...]
        }
        guard let magnitude = UInt(digits, radix: radix) else { return nil }
        if negative {
            if magnitude == Int.min.magnitude { return Int.min }
            guard let value = Int(exactly: magnitude) else { return nil }
            return -value
        }
        return Int(exactly: magnitude)
    }
}
