import SwiftTLA

extension NativeSwiftEmitter {
    /// Keep predicate trees shallow in generated Swift while preserving lazy operands.
    mutating func booleanExpression(
        _ root: NativeExpressionID, state: String, substitutions: [BinderID: String],
        activeFunctions: Set<NativeFunctionID>
    ) throws -> String {
        var pending = [root]
        var declarations: [String] = []
        while let id = pending.popLast() {
            let node = program[id]
            let body: String
            switch node.expression {
            case .and, .or:
                let conjunction: Bool = if case .and = node.expression { true } else { false }
                let left = node.children[0]
                let right = node.children[1]
                let condition = conjunction ? "left" : "!left"
                let earlyResult = conjunction ? "false" : "true"
                body = """
                let left = try _predicate\(left.ordinal)()
                guard \(condition) else { return \(earlyResult) }
                return try _predicate\(right.ordinal)()
                """
                pending.append(contentsOf: [right, left])
            default:
                let value = try expression(id, state: state, substitutions: substitutions, activeFunctions: activeFunctions)
                body = "return \(value)"
            }
            declarations.append("""
            func _predicate\(id.ordinal)() throws -> Bool {
                \(body)
            }
            """)
        }
        return """
        (try { () throws -> Bool in
            \(declarations.joined(separator: "\n"))
            return try _predicate\(root.ordinal)()
        }())
        """
    }
}
