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
        case (.record(let inputs), .record(let outputs)) where inputs.map(\.name) == outputs.map(\.name):
            return try checkedFields(value, from: source, to: target, inputs: inputs.map(\.type), outputs: outputs.map(\.type))
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
        let cases = try alternatives.enumerated().map { index, alternative in
            "case (.\(unionCase(type, index: index))(let left), .\(unionCase(type, index: index))(let right)): return (\(try ordering(alternative)))(left, right)"
        }.joined(separator: "\n")
        let rank = try unionRank("value", type: type, members: finiteViewMembers(type))
        return """
        func rank(_ value: \(try swiftType(type))) -> (Int, Int) { return \(rank) }
        switch (lhs, rhs) { \(cases)
        default: return rank(lhs) < rank(rhs)
        }
        """
    }

    private func unionRank(_ value: String, type: CompiledValueType, members: [CompiledValue]) throws -> String {
        if let ordinal = try finiteUnionRank(value, type: type, members: members) {
            return "(\(try formalKindRank(value, type: type)), { () -> Int in \(ordinal) }())"
        }
        if let alternatives = type.unionAlternatives {
            let cases = try alternatives.enumerated().map { index, alternative in
                "case .\(unionCase(type, index: index))(let payload): return \(try unionRank("payload", type: alternative, members: members))"
            }.joined(separator: "\n")
            return "({ () -> (Int, Int) in switch \(value) { \(cases) } }())"
        }
        return "(\(try formalKindRank(value, type: type)), 0)"
    }

    private func finiteUnionRank(_ value: String, type: CompiledValueType, members: [CompiledValue]) throws -> String? {
        if let alternatives = type.unionAlternatives {
            var cases: [String] = []
            for (index, alternative) in alternatives.enumerated() {
                guard let nested = try finiteUnionRank("payload", type: alternative, members: members) else { return nil }
                cases.append("case .\(unionCase(type, index: index))(let payload): \(nested)")
            }
            return "switch \(value) { \(cases.joined(separator: "\n")) }"
        }
        let cases: [String]
        switch type {
        case .named(let name):
            guard let values = program.enums.cases[name] else { return nil }
            cases = try values.map { item in
                guard let rank = members.firstIndex(of: item.value) else { throw unsupported("union ordering member") }
                return "case .`\(item.name)`: return \(rank)"
            }
        case .finite(let values):
            cases = try values.enumerated().map { index, item in
                guard let rank = members.firstIndex(of: item) else { throw unsupported("union ordering member") }
                return "case .\(finiteCaseName(values, index: index)): return \(rank)"
            }
        default: return nil
        }
        return "switch \(value) { \(cases.joined(separator: "\n")) }"
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
