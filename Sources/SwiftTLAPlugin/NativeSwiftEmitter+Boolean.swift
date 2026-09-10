import SwiftTLA

extension NativeSwiftEmitter {
    /// Keep predicate trees shallow in generated Swift while preserving lazy operands.
    mutating func booleanExpression(
        _ root: NativeCheckedExpression, state: String, substitutions: [BinderID: String],
        activeFunctions: Set<NativeFunctionID>
    ) throws -> String {
        var pending = [root]
        var declarations: [String] = []
        var emitted: Set<NativeCheckedExpression> = []
        while let id = pending.popLast() {
            guard emitted.insert(id).inserted else { continue }
            let node = id
            let body: String
            switch node.expression {
            case .and, .or:
                let conjunction: Bool = if case .and = node.expression { true } else { false }
                let left = node.children[0]
                let right = node.children[1]
                let condition = conjunction ? "left" : "!left"
                let earlyResult = conjunction ? "false" : "true"
                body = """
                let left = try _predicate\(expressionOrdinals[left]!)()
                guard \(condition) else { return \(earlyResult) }
                return try _predicate\(expressionOrdinals[right]!)()
                """
                pending.append(contentsOf: [right, left])
            default:
                let value = try expression(id, state: state, substitutions: substitutions, activeFunctions: activeFunctions)
                body = "return \(value)"
            }
            declarations.append("""
            func _predicate\(expressionOrdinals[id]!)() throws -> Bool {
                \(body)
            }
            """)
        }
        return """
        (try { () throws -> Bool in
            \(declarations.joined(separator: "\n"))
            return try _predicate\(expressionOrdinals[root]!)()
        }())
        """
    }
}
