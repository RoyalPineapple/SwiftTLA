extension StraightLineRenderedActionCheck {
    // shortcut: pure append/concatenation trees only; fallible children need their own output rules.
    static func sequenceValue(_ expression: CompiledExpression,
                              variables: [VariableID: String],
                              binders: [BinderID: String]) -> String? {
        guard expression.operation == .tupleAppend || expression.operation == .tupleConcatenate else {
            return nil
        }
        var pending = [(expression, false)]
        var values: [String] = []
        while let (node, expanded) = pending.popLast() {
            if expanded {
                let count = node.children.count
                guard values.count >= count else { return nil }
                let children = Array(values.suffix(count))
                values.removeLast(count)
                switch node.operation {
                case .tupleLiteral:
                    values.append("<<\(children.joined(separator: ", "))>>")
                case .tupleAppend where count == 2:
                    values.append("Append(\(children[0]), \(children[1]))")
                case .tupleConcatenate where count == 2:
                    values.append("(\(children[0]) \\o \(children[1]))")
                default: return nil
                }
                continue
            }
            switch node.operation {
            case .tupleAppend, .tupleConcatenate:
                guard node.children.count == 2 else { return nil }
                pending.append((node, true))
                pending.append(contentsOf: node.children.reversed().map { ($0, false) })
            case .tupleLiteral:
                pending.append((node, true))
                pending.append(contentsOf: node.children.reversed().map { ($0, false) })
            case .stateVariable(let id) where node.children.isEmpty:
                guard let name = variables[id] else { return nil }
                values.append(name)
            case .boundValue(let id) where node.children.isEmpty:
                guard let name = binders[id] else { return nil }
                values.append(name)
            case .value(.integer(let value)) where node.children.isEmpty:
                guard (-1_000_000_000...1_000_000_000).contains(value) else { return nil }
                values.append(String(value))
            case .value(.tuple(let elements)) where node.children.isEmpty:
                var literals: [String] = []
                for element in elements {
                    guard case .integer(let value) = element,
                          (-1_000_000_000...1_000_000_000).contains(value) else { return nil }
                    literals.append(String(value))
                }
                values.append("<<\(literals.joined(separator: ", "))>>")
            default: return nil
            }
        }
        return values.count == 1 ? values[0] : nil
    }
}
