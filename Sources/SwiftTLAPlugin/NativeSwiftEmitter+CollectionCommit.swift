import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    /// Stage a single append or point write. Every expression that can throw runs
    /// against the original snapshot, before its collection storage is released.
    mutating func collectionCommit(_ action: CompiledAction, configurationParameters: String) throws -> DeclSyntax? {
        guard action.bindings.isEmpty else { return nil }
        var pending = [action.body]
        var prefix: [String] = []
        var writes: Set<VariableID> = []
        var values: [VariableID: String] = [:]
        var collection: VariableID?
        var deferredBinder: BinderID?
        var applied = false
        var empty = "", mutation = ""
        var operands: [(name: String, type: String)] = []

        func supports(_ expression: CompiledExpression) -> Bool {
            var remaining = [expression]
            while let node = remaining.popLast() {
                switch node.operation {
                case .boundValue(let binder) where binder == deferredBinder: return false
                case .value, .stateVariable, .boundValue, .controlLocation, .convert,
                     .add, .subtract, .multiply, .divide, .integerDivide, .modulo, .negate,
                     .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
                     .and, .or, .not, .ifThenElse, .recordLiteral, .recordAccess, .except,
                     .functionApply, .tupleAppend, .tupleLength, .tupleHead: break
                default: return false
                }
                remaining.append(contentsOf: node.children)
            }
            return true
        }
        func target(of node: CompiledExpression) -> VariableID? {
            guard collection == nil, let base = node.children.first,
                  case .stateVariable(let id) = base.operation else { return nil }
            switch (node.operation, base.resultType) {
            case (.tupleAppend, .array), (.except, .dictionary(.int, .int)): return id
            default: return nil
            }
        }
        func evaluate(_ node: CompiledExpression, as name: String, keep: Bool = true) throws {
            if keep { operands.append((name, try swiftType(node.resultType))) }
            prefix.append("let \(name): \(try swiftType(node.resultType)) = \(try expression(node, state: "state."))")
        }
        func stage(_ node: CompiledExpression, at id: VariableID) throws {
            collection = id
            if node.operation == .tupleAppend {
                try evaluate(node.children[1], as: "_element")
                empty = "[]"
                mutation = "_buffer.append(_element)"
            } else {
                // EXCEPT evaluates the replacement before the key, even if the key is absent.
                try evaluate(node.children[2], as: "_element")
                try evaluate(node.children[1], as: "_key")
                empty = "[:]"
                mutation = "if _buffer[_key] != nil { _buffer[_key] = _element }"
            }
        }
        while let part = pending.popLast() {
            switch part {
            case .and(let first, let second):
                pending.append(second)
                pending.append(first)
            case .guard_(let predicate):
                guard supports(predicate), predicate.booleanConstant != false else { return nil }
                if predicate.booleanConstant != true {
                    prefix.append("guard \(try expression(predicate, state: "state.")) else { return nil }")
                }
            case .define(let binding, let rhs, let body):
                guard supports(rhs) else { return nil }
                if let id = target(of: rhs) {
                    try stage(rhs, at: id)
                    deferredBinder = binding
                } else {
                    try evaluate(rhs, as: binder(binding), keep: false)
                    prefix.append("_ = \(binder(binding))")
                }
                pending.append(body)
            case .assign(let slot, let rhs):
                guard writes.insert(slot).inserted else { return nil }
                if case .boundValue(let binding) = rhs.operation, binding == deferredBinder, slot == collection {
                    applied = true
                } else {
                    guard supports(rhs) else { return nil }
                    if target(of: rhs) == slot {
                        try stage(rhs, at: slot)
                        applied = true
                    } else {
                        let name = "_staged\(slot.ordinal)"
                        try evaluate(rhs, as: name)
                        values[slot] = name
                    }
                }
            case .unchanged(let slot):
                guard writes.insert(slot).inserted else { return nil }
            default: return nil
            }
        }
        guard applied, let collection, values[collection] == nil else { return nil }
        let release = executionState { $0 == collection ? empty : stateValue($0) }
        let result = executionState { $0 == collection ? "_buffer" : values[$0] ?? stateValue($0) }
        let names = operands.map(\.name).joined(separator: ", ")
        let types = operands.map(\.type).joined(separator: ", ")
        return DeclSyntax(stringLiteral: """
        private static func _commit\(action.id.ordinal)(_ state: inout Snapshot\(configurationParameters)) throws -> \(nativeBoolType) {
            func prepare(_ state: Snapshot) throws -> (\(types))? {
                \(prefix.joined(separator: "\n"))
                return (\(names))
            }
            func install(_ prepared: (\(types)), into state: inout Snapshot) {
                let (\(names)) = prepared
                var _buffer = \(stateValue(collection))
                state = \(release)
                \(mutation)
                state = \(result)
            }
            guard let prepared = try prepare(state) else { return false }
            install(prepared, into: &state)
            return true
        }
        """)
    }
}
