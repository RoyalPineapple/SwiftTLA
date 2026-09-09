import SwiftTLA

extension NativeSwiftEmitter {
    mutating func checkedView(_ value: String, from source: NativeType, to target: NativeType) throws -> String {
        if program.canProject(source: source, to: target) { return try projected(value, from: source, to: target) }
        if case .union = source { return try unionProjection(value, from: source, to: target, checked: true) }
        if case .finite(let members) = source {
            let cases = try members.indices.map { index in
                let result: String
                if let literal = try? literal(members[index], as: target) { result = "return \(literal)" }
                else { result = "throw NativeMachineEvaluationError.noMatchingCase" }
                return "case .\(finiteCaseName(members, index: index)): \(result)"
            }.joined(separator: "\n")
            return "(try { (value: \(try swiftType(source))) throws -> \(try swiftType(target)) in switch value { \(cases) } }(\(value)))"
        }
        if case .named(let name) = source,
           let info = model.enumInfos.first(where: { $0.typeName == name }) {
            let cases = info.cases.map { item in
                let payload = try? literal(CompiledValue(formal: item.value), as: target)
                return "case .`\(item.name)`: " + (payload.map { "return " + $0 } ?? "throw NativeMachineEvaluationError.noMatchingCase")
            }.joined(separator: "\n")
            return "(try { (value: \(try swiftType(source))) throws -> \(try swiftType(target)) in switch value { \(cases) } }(\(value)))"
        }
        if [.int, .bool, .string, .atom].contains(source) {
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

    func finiteViewMembers(_ type: NativeType) -> [CompiledValue] {
        switch type {
        case .finite(let members): return members
        case .named(let name): return model.enumInfos.first(where: { $0.typeName == name })?.cases.map { CompiledValue(formal: $0.value) } ?? []
        case .union(let alternatives): return Array(Set(alternatives.flatMap(finiteViewMembers))).sorted()
        default: return []
        }
    }

    mutating func checkedFields(_ value: String, from source: NativeType, to target: NativeType, inputs: [NativeType], outputs: [NativeType]) throws -> String {
        let fields = try inputs.indices.map { index in
            "\(fieldName(target, index: index)): \(try checkedView("value." + fieldName(source, index: index), from: inputs[index], to: outputs[index]))"
        }.joined(separator: ", ")
        return "(try { (value: \(try swiftType(source))) throws -> \(try swiftType(target)) in \(try swiftType(target))(\(fields)) }(\(value)))"
    }

    mutating func unionProjection(_ value: String, from source: NativeType, to target: NativeType, checked: Bool) throws -> String {
        guard case .union(let alternatives) = source else { throw unsupported("union projection source") }
        let cases = try alternatives.enumerated().map { index, alternative in
            let payload = checked
                ? try checkedView("payload", from: alternative, to: target)
                : try projected("payload", from: alternative, to: target)
            return "case .alternative\(index + 1)(let payload): return \(payload)"
        }.joined(separator: "\n")
        let throwing = checked ? " throws" : ""
        let prefix = checked ? "try " : ""
        return "(\(prefix){ (value: \(try swiftType(source)))\(throwing) -> \(try swiftType(target)) in switch value { \(cases) } }(\(value)))"
    }

    mutating func unionOrdering(_ alternatives: [NativeType]) throws -> String {
        let cases = try alternatives.enumerated().map { index, alternative in
            "case (.alternative\(index + 1)(let left), .alternative\(index + 1)(let right)): return (\(try ordering(alternative)))(left, right)"
        }.joined(separator: "\n")
        let ranks = try alternatives.enumerated().map { index, alternative in
            "case .alternative\(index + 1)(let payload): return \(try formalKindRank("payload", type: alternative))"
        }.joined(separator: "\n")
        return """
        func rank(_ value: \(try swiftType(.union(alternatives)))) -> Int { switch value { \(ranks) } }
        switch (lhs, rhs) { \(cases)
        default: return rank(lhs) < rank(rhs)
        }
        """
    }

    mutating func formalKindRank(_ value: String, type: NativeType) throws -> String {
        let representative: CompiledValue
        switch type {
        case .int: representative = .integer(0)
        case .bool: representative = .boolean(false)
        case .string: representative = .string("")
        case .atom: representative = .constant("")
        case .set: representative = .set([])
        case .array, .tuple: representative = .tuple([])
        case .dictionary: representative = .function([:])
        case .record: representative = CompiledValue(formal: .record([:]))
        case .finite(let members):
            let cases = members.indices.map { "case .\(finiteCaseName(members, index: $0)): return \(members[$0].orderingKind)" }.joined(separator: "\n")
            return "({ (value: \(try swiftType(type))) -> Int in switch value { \(cases) } })(\(value))"
        case .named(let name):
            guard let info = model.enumInfos.first(where: { $0.typeName == name }) else { throw unsupported("union enum rank") }
            let cases = info.cases.map { "case .`\($0.name)`: return \(CompiledValue(formal: $0.value).orderingKind)" }.joined(separator: "\n")
            return "({ (value: \(name)) -> Int in switch value { \(cases) } })(\(value))"
        default: throw unsupported("union alternative order")
        }
        return String(representative.orderingKind)
    }
}
