import SwiftTLA

extension NativeSwiftEmitter {
    /// Keep predicate trees shallow in generated Swift while preserving lazy operands.
    mutating func booleanExpression(
        _ root: CompiledExpression, state: String, substitutions: [BinderID: String],
        activeFunctions: Set<ResolvedFunctionID>
    ) throws -> String {
        var pending = [root]
        var declarations: [String] = []
        var emitted: Set<CompiledExpression> = []
        while let id = pending.popLast() {
            guard emitted.insert(id).inserted else { continue }
            let node = id
            let body: String
            switch node.operation {
            case .and, .or:
                let left = node.children[0]
                let right = node.children[1]
                let operation: String = if case .and = node.operation { "booleanAnd" } else { "booleanOr" }
                body = "return try SwiftTLA._NativeMachineOperations.\(operation)({ try _predicate\(ordinal(for: left))() }, { try _predicate\(ordinal(for: right))() })"
                pending.append(contentsOf: [right, left])
            case .ifThenElse where node.resultType == .bool:
                let condition = node.children[0]
                let yes = node.children[1]
                let no = node.children[2]
                body = "return try SwiftTLA._NativeMachineOperations.booleanIf({ try _predicate\(ordinal(for: condition))() }, ifTrue: { try _predicate\(ordinal(for: yes))() }, ifFalse: { try _predicate\(ordinal(for: no))() })"
                pending.append(contentsOf: [no, yes, condition])
            case .not:
                let child = node.children[0]
                body = "return try SwiftTLA._NativeMachineOperations.booleanNot { try _predicate\(ordinal(for: child))() }"
                pending.append(child)
            default:
                let value = try expression(id, state: state, substitutions: substitutions, activeFunctions: activeFunctions)
                body = "return \(value)"
            }
            declarations.append("""
            func _predicate\(ordinal(for: id))() throws -> Bool {
                \(body)
            }
            """)
        }
        return """
        (try { () throws -> Bool in
            \(declarations.joined(separator: "\n"))
            return try _predicate\(ordinal(for: root))()
        }())
        """
    }
}
