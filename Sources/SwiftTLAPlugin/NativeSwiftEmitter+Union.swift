import SwiftTLA

extension NativeSwiftEmitter {
    func unionCase(_ type: CompiledValueType, index: Int) -> String {
        if case .oneOf = type { return index == 0 ? "first" : "second" }
        return "alternative\(index + 1)"
    }

    func unionValue(_ payload: String, type: CompiledValueType, index: Int) throws -> String {
        let name = try swiftType(type)
        let value = "\(name).\(unionCase(type, index: index))(\(payload))"
        if case .oneOf = type { return "(\(value) as \(name))" }
        return value
    }

    func checkedView(_ value: String, from source: CompiledValueType, to target: CompiledValueType) throws -> String {
        if program.canProject(source: source, to: target) { return try projected(value, from: source, to: target) }
        if source.unionAlternatives != nil { return try unionProjection(value, from: source, to: target, checked: true) }
        if case .finite(let members) = source {
            let cases = members.indices.map { index in
                let result: String
                if let literal = try? literal(members[index], as: target) { result = "return \(literal)" }
                else { result = "throw NativeMachineEvaluationError.noMatchingCase" }
                return "case .\(finiteCaseName(members, index: index)): \(result)"
            }.joined(separator: "\n")
            return "(try { (value: \(try swiftType(source))) throws -> \(try swiftType(target)) in switch value { \(cases) } }(\(value)))"
        }
        if case .named(let name) = source,
           let members = program.enums.cases[name] {
            let cases = members.map { item in
                let payload = try? literal(item.value, as: target)
                return "case .`\(item.name)`: " + (payload.map { "return " + $0 } ?? "throw NativeMachineEvaluationError.noMatchingCase")
            }.joined(separator: "\n")
            return "(try { (value: \(try swiftType(source))) throws -> \(try swiftType(target)) in switch value { \(cases) } }(\(value)))"
        }
        if [.int, .bool, .string, .modelValue].contains(source) {
            let cases = finiteViewMembers(target).compactMap { member -> String? in
                guard let pattern = try? literal(member, as: source), let payload = try? literal(member, as: target) else { return nil }
                return "case \(pattern): return \(payload)"
            }.joined(separator: "\n")
            return "(try { (value: \(try swiftType(source))) throws -> \(try swiftType(target)) in switch value { \(cases)\ndefault: throw NativeMachineEvaluationError.noMatchingCase } }(\(value)))"
        }
        if let inputs = source.recordFields, let outputs = target.recordFields,
           inputs.map(\.name) == outputs.map(\.name) {
            return try checkedFields(value, from: source, to: target,
                                     inputs: inputs.map(\.type), outputs: outputs.map(\.type))
        }
        switch (source, target) {
        case (.set(let input), .set(let output)):
            return "Set<\(try swiftType(output))>(try (\(value)).map { element in \(try checkedView("element", from: input, to: output)) })"
        case (.array(let input), .array(let output)):
            return "(try (\(value)).map { element in \(try checkedView("element", from: input, to: output)) })"
        case (.dictionary(let sourceKey, let sourceValue), .dictionary(let targetKey, let targetValue)):
            let key = try checkedView("entry.key", from: sourceKey, to: targetKey)
            let item = try checkedView("entry.value", from: sourceValue, to: targetValue)
            return "Dictionary<\(try swiftType(targetKey)), \(try swiftType(targetValue))>(uniqueKeysWithValues: try (\(value)).map { entry in (\(key), \(item)) })"
        case (.tuple(let inputs), .tuple(let outputs)) where inputs.count == outputs.count:
            return try checkedFields(value, from: source, to: target, inputs: inputs, outputs: outputs)
        default:
            return "(try { (_: \(try swiftType(source))) throws -> \(try swiftType(target)) in throw NativeMachineEvaluationError.noMatchingCase }(\(value)))"
        }
    }

    func finiteViewMembers(_ type: CompiledValueType) -> [CompiledValue] {
        switch type {
        case .finite(let members): return members
        case .named(let name): return program.enums.cases[name]?.map(\.value) ?? []
        case .union(let alternatives): return Array(Set(alternatives.flatMap(finiteViewMembers))).sorted()
        case .oneOf(let first, let second): return Array(Set(finiteViewMembers(first) + finiteViewMembers(second))).sorted()
        default: return []
        }
    }

    func checkedFields(_ value: String, from source: CompiledValueType, to target: CompiledValueType, inputs: [CompiledValueType], outputs: [CompiledValueType]) throws -> String {
        let fields = try inputs.indices.map { index in
            "\(fieldName(target, index: index, escaped: false)): \(try checkedView("value." + fieldName(source, index: index), from: inputs[index], to: outputs[index]))"
        }.joined(separator: ", ")
        return "(try { (value: \(try swiftType(source))) throws -> \(try swiftType(target)) in \(try swiftType(target))(\(fields)) }(\(value)))"
    }

    func unionProjection(_ value: String, from source: CompiledValueType, to target: CompiledValueType, checked: Bool) throws -> String {
        guard let alternatives = source.unionAlternatives else { throw unsupported("union projection source") }
        let cases = try alternatives.enumerated().map { index, alternative in
            let payload = checked
                ? try checkedView("payload", from: alternative, to: target)
                : try projected("payload", from: alternative, to: target)
            return "case .\(unionCase(source, index: index))(let payload): return \(payload)"
        }.joined(separator: "\n")
        let throwing = checked ? " throws" : ""
        let prefix = checked ? "try " : ""
        return "(\(prefix){ (value: \(try swiftType(source)))\(throwing) -> \(try swiftType(target)) in switch value { \(cases) } }(\(value)))"
    }

    func unionOrdering(_ type: CompiledValueType) throws -> String {
        guard let alternatives = type.unionAlternatives else { throw unsupported("union ordering source") }
        let cases = try alternatives.enumerated().flatMap { leftIndex, left in
            try alternatives.enumerated().map { rightIndex, right in
                "case (.\(unionCase(type, index: leftIndex))(let left), .\(unionCase(type, index: rightIndex))(let right)): return (\(try crossOrdering(left, right)))(left, right)"
            }
        }
        return "switch (lhs, rhs) { \(cases.joined(separator: "\n")) }"
    }

    private func crossOrdering(_ left: CompiledValueType, _ right: CompiledValueType) throws -> String {
        if left == right { return try ordering(left) }
        func closure(_ body: String) throws -> String {
            "{ (lhs: \(try swiftType(left)), rhs: \(try swiftType(right))) -> Bool in \(body) }"
        }
        func compare(_ lhs: String, _ left: CompiledValueType, _ rhs: String, _ right: CompiledValueType) throws -> String {
            "if (\(try crossOrdering(left, right)))(\(lhs), \(rhs)) { return true }; if (\(try crossOrdering(right, left)))(\(rhs), \(lhs)) { return false }"
        }
        if let alternatives = left.unionAlternatives {
            let cases = try alternatives.enumerated().map { index, alternative in
                "case .\(unionCase(left, index: index))(let payload): return (\(try crossOrdering(alternative, right)))(payload, rhs)"
            }.joined(separator: "\n")
            return try closure("switch lhs { \(cases) }")
        }
        if let alternatives = right.unionAlternatives {
            let cases = try alternatives.enumerated().map { index, alternative in
                "case .\(unionCase(right, index: index))(let payload): return (\(try crossOrdering(left, alternative)))(lhs, payload)"
            }.joined(separator: "\n")
            return try closure("switch rhs { \(cases) }")
        }
        func members(_ type: CompiledValueType) -> [(name: String, value: CompiledValue)]? {
            switch type {
            case .named(let name): return program.enums.cases[name]?.map { ("`\($0.name)`", $0.value) }
            case .finite(let values): return values.enumerated().map { (finiteCaseName(values, index: $0.offset), $0.element) }
            default: return nil
            }
        }
        if let a = members(left), let b = members(right) {
            let ordered = Set((a + b).map(\.value)).sorted()
            let ranks = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
            func cases(_ values: [(name: String, value: CompiledValue)]) -> String {
                values.map { "case .\($0.name): return \(ranks[$0.value]!)" }.joined(separator: "\n")
            }
            return try closure("""
            func leftRank(_ value: \(try swiftType(left))) -> Int { switch value { \(cases(a)) } }
            func rightRank(_ value: \(try swiftType(right))) -> Int { switch value { \(cases(b)) } }
            return leftRank(lhs) < rightRank(rhs)
            """)
        }
        if let values = members(left) ?? members(right) {
            let fromLeft = members(left) != nil
            let other = fromLeft ? right : left
            let valueName = fromLeft ? "rhs" : "lhs"
            let rank = try formalKindRank(valueName, type: other)
            let cases = try values.map { item in
                let result: String
                if let value = try? literal(item.value, as: other) {
                    result = "(\(try ordering(other)))(\(fromLeft ? value : valueName), \(fromLeft ? valueName : value))"
                } else {
                    guard rank != String(item.value.orderingKind) else {
                        throw unsupported("ordering finite value against incompatible composite shape")
                    }
                    result = fromLeft ? "\(item.value.orderingKind) < \(rank)" : "\(rank) < \(item.value.orderingKind)"
                }
                return "case .\(item.name): return \(result)"
            }
            return try closure("switch \(fromLeft ? "lhs" : "rhs") { \(cases.joined(separator: "\n")) }")
        }
        if let a = left.recordFields, let b = right.recordFields {
            var body = ""
            for (x, y) in zip(a.sorted { $0.name < $1.name }, b.sorted { $0.name < $1.name }) {
                if x.name != y.name { return try closure(body + "return \(x.name < y.name)") }
                body += try compare("lhs.`\(x.name)`", x.type, "rhs.`\(y.name)`", y.type) + "\n"
            }
            return try closure(body + "return \(a.count < b.count)")
        }
        switch (left, right) {
        case (.array(let a), .array(let b)), (.set(let a), .set(let b)):
            let isSet: Bool = if case .set = left { true } else { false }
            let lhs = isSet ? "lhs.sorted(by: \(try ordering(a)))" : "lhs"
            let rhs = isSet ? "rhs.sorted(by: \(try ordering(b)))" : "rhs"
            return try closure("for (a, b) in zip(\(lhs), \(rhs)) { \(try compare("a", a, "b", b)) }; return lhs.count < rhs.count")
        case (.dictionary(let ak, let av), .dictionary(let bk, let bv)):
            return try closure("""
            let a = lhs.sorted { (\(try ordering(ak)))($0.key, $1.key) }
            let b = rhs.sorted { (\(try ordering(bk)))($0.key, $1.key) }
            for (x, y) in zip(a, b) {
                \(try compare("x.key", ak, "y.key", bk))
                \(try compare("x.value", av, "y.value", bv))
            }
            return lhs.count < rhs.count
            """)
        case (.tuple(let a), .tuple(let b)):
            let fields = try zip(a, b).enumerated().map { index, types in
                try compare("lhs." + fieldName(left, index: index), types.0, "rhs." + fieldName(right, index: index), types.1)
            }.joined(separator: "\n")
            return try closure(fields + "\nreturn \(a.count < b.count)")
        default:
            let a = try formalKindRank("lhs", type: left)
            let b = try formalKindRank("rhs", type: right)
            guard a != b else { throw unsupported("ordering incompatible shapes of the same formal kind") }
            return try closure("return \(a) < \(b)")
        }
    }

    func formalKindRank(_ value: String, type: CompiledValueType) throws -> String {
        let representative: CompiledValue
        switch type {
        case .int: representative = .integer(0)
        case .bool: representative = .boolean(false)
        case .string: representative = .string("")
        case .modelValue: representative = .constant("")
        case .set: representative = .set([])
        case .array, .tuple: representative = .tuple([])
        case .dictionary: representative = .function([:])
        case .record, .nominalRecord: representative = CompiledValue(formal: .record([:]))
        case .oneOf, .union:
            guard let alternatives = type.unionAlternatives else { throw unsupported("union alternative order") }
            let cases = try alternatives.enumerated().map { index, alternative in
                "case .\(unionCase(type, index: index))(let payload): return \(try formalKindRank("payload", type: alternative))"
            }.joined(separator: "\n")
            return "({ (value: \(try swiftType(type))) -> Int in switch value { \(cases) } })(\(value))"
        case .finite(let members):
            let cases = members.indices.map { "case .\(finiteCaseName(members, index: $0)): return \(members[$0].orderingKind)" }.joined(separator: "\n")
            return "({ (value: \(try swiftType(type))) -> Int in switch value { \(cases) } })(\(value))"
        case .named(let name):
            guard let members = program.enums.cases[name] else { throw unsupported("union enum rank") }
            let cases = members.map { "case .`\($0.name)`: return \($0.value.orderingKind)" }.joined(separator: "\n")
            return "({ (value: \(name)) -> Int in switch value { \(cases) } })(\(value))"
        default: throw unsupported("union alternative order")
        }
        return String(representative.orderingKind)
    }
}
