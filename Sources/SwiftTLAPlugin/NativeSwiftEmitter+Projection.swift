import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    /// Serialize resolved native values only at the independent validation boundary.
    func formalProjectionDeclarations() throws -> [DeclSyntax] {
        let entries = try program.layout.variables.map { variable in
            let name = variable.declaration.name
            guard TLAStateProjection.Token(validating: name) != nil else {
                throw unsupported("invalid formal state identifier: \(name)")
            }
            let value = try formalValue(stateValue(variable.id, prefix: "snapshot."), type: program.variableTypes[variable.id]!)
            return ".init(token: TLAStateProjection.Token(validating: \(String(reflecting: name)))!, value: \(value))"
        }.joined(separator: ",\n")
        return [DeclSyntax(stringLiteral: """
        public func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection {
            try TLAStateProjection(validating: [\(entries)])
        }
        """)]
    }

    private func formalValue(_ value: String, type: CompiledValueType) throws -> String {
        func switching(_ cases: [String]) -> String {
            "try { () throws -> TLAValue in switch \(value) {\n\(cases.joined(separator: "\n"))\n} }()"
        }
        switch type {
        case .int: return "TLAValue.int(\(value))"
        case .bool: return "TLAValue.bool(\(value))"
        case .string: return "TLAValue.string(\(value))"
        case .atom: return "TLAValue.constant(\(value).rawValue)"
        case .control:
            return switching(program.layout.controlLocations.map {
                "case .location\($0.id.ordinal): return .string(\(String(reflecting: $0.sourceName)))"
            })
        case .named(let name):
            guard let members = program.enums.cases[name] else { throw unsupported("unresolved formal enum: \(name)") }
            return switching(try members.map {
                "case .`\($0.name)`: return \(try formalLiteral($0.value))"
            })
        case .finite(let members):
            return switching(try members.indices.map {
                "case .\(finiteCaseName(members, index: $0)): return \(try formalLiteral(members[$0]))"
            })
        case .union(let alternatives):
            return switching(try alternatives.enumerated().map {
                "case .alternative\($0.offset + 1)(let payload): return \(try formalValue("payload", type: $0.element))"
            })
        case .collectionMember(let variable, _):
            guard let collection = model.surface.variables.first(where: { $0.id == variable })?.collection else {
                throw unsupported("unresolved formal collection")
            }
            let members = try collection.members.map(formalLiteral).joined(separator: ", ")
            return """
            try { () throws -> TLAValue in
                guard let index = \(collection.membersIdentifier).firstIndex(of: \(value)) else {
                    throw TLAStateProjectionDiagnostic.invalidValue(path: \(String(reflecting: collection.swiftIdentifier)))
                }
                return [TLAValue]([\(members)])[index]
            }()
            """
        case .set(let element):
            return "TLAValue.set(try Set(\(value).map { (element) throws -> TLAValue in \(try formalValue("element", type: element)) }))"
        case .array(let element):
            return "TLAValue.tuple(try \(value).map { (element) throws -> TLAValue in \(try formalValue("element", type: element)) })"
        case .tuple(let elements):
            let values = try elements.enumerated().map {
                try formalValue(value + "." + fieldName(type, index: $0.offset), type: $0.element)
            }
            return "TLAValue.tuple([\(values.joined(separator: ", "))])"
        case .record(let fields):
            let values = try fields.enumerated().map {
                ".init(\(String(reflecting: $0.element.name)), \(try formalValue(value + "." + fieldName(type, index: $0.offset), type: $0.element.type)))"
            }
            return "TLAValue.record(TLARecord([\(values.joined(separator: ", "))]))"
        case .dictionary(let key, let element):
            return """
            TLAValue.function(try \(value).reduce(into: [TLAValue: TLAValue]()) { result, entry in
                let key = \(try formalValue("entry.key", type: key))
                let value = \(try formalValue("entry.value", type: element))
                guard result.updateValue(value, forKey: key) == nil else {
                    throw TLAStateProjectionDiagnostic.invalidValue(path: "duplicate formal function key")
                }
            })
            """
        case .unknown: throw unsupported("unresolved formal projection type")
        }
    }

    private func formalLiteral(_ value: CompiledValue) throws -> String {
        func emit(_ value: TLAValue) -> String {
            switch value {
            case .int(let value): return "TLAValue.int(\(value == Int.min ? "Int.min" : String(value)))"
            case .bool(let value): return "TLAValue.bool(\(value))"
            case .string(let value): return "TLAValue.string(\(String(reflecting: value)))"
            case .constant(let value): return "TLAValue.constant(\(String(reflecting: value)))"
            case .set(let values): return "TLAValue.set([\(values.sorted().map(emit).joined(separator: ", "))])"
            case .tuple(let values): return "TLAValue.tuple([\(values.map(emit).joined(separator: ", "))])"
            case .record(let fields): return "TLAValue.record(TLARecord([\(fields.fields.map { ".init(\(String(reflecting: $0.name)), \(emit($0.value)))" }.joined(separator: ", "))]))"
            case .function(let values):
                let entries = values.sorted { $0.key < $1.key }.map { "\(emit($0.key)): \(emit($0.value))" }
                return "TLAValue.function([\(entries.isEmpty ? ":" : entries.joined(separator: ", "))])"
            }
        }
        return emit(try value.rendered(using: program.layout))
    }
}
