import SwiftSyntax
import SwiftParser
import SwiftTLA
import SwiftTLACompilerSupport

extension NativeSwiftEmitter {
    /// Serialize resolved native values only at the independent validation boundary.
    func formalProjectionDeclarations() throws -> [DeclSyntax] {
        let fields = try program.layout.variables.map { variable in
            let name = variable.formalName
            guard TLAStateProjection.Token(validating: name) != nil else {
                throw unsupported("invalid formal state identifier: \(name)")
            }
            let route = stateValue(variable.id, prefix: "snapshot.")
            let type = program.variableTypes[variable.id]!
            return (formalName: name, route: route, type: type)
        }
        let tokens = fields.map { field in
            "SwiftTLA._nativeFormalProjectionToken(validating: \(String(reflecting: field.formalName)))!"
        }.joined(separator: ", ")
        let table = DeclSyntax(stringLiteral: """
        private static let __swifttlaFormalProjectionTokens: [SwiftTLA.TLAStateProjection.Token] = [\(tokens)]
        """)
        if fields.contains(where: { hasConstantFunctionDomain($0.type) }) {
            return try sharedProjectionDeclarations(table: table, fields: fields)
        }
        let projected = try fields.map { (formalName: $0.formalName, route: $0.route, type: $0.type, value: try formalValue($0.route, type: $0.type)) }
        let entries = projected.enumerated().map { index, field in
            "SwiftTLA._nativeFormalProjectionEntry(Self.__swifttlaFormalProjectionTokens, at: \(index), value: \(field.value))"
        }.joined(separator: ",\n")
        let declarations = [table, DeclSyntax(stringLiteral: """
        public func formalProjection(of snapshot: Snapshot) throws -> SwiftTLA.TLAStateProjection {
            try SwiftTLA._nativeFormalProjection([\(entries)])
        }
        """)]
        try verifyGeneratedFormalProjectionOutput(declarations, fields: projected)
        return declarations
    }

    func formalValue(_ value: String, type: CompiledValueType) throws -> String {
        func switching(_ cases: [String]) -> String {
            "try { () throws -> SwiftTLA.TLAValue in switch \(value) {\n\(cases.joined(separator: "\n"))\n} }()"
        }
        switch type {
        case .int: return "SwiftTLA._nativeFormalInt(\(value))"
        case .bool: return "SwiftTLA.TLAValue.bool(\(value))"
        case .string: return "SwiftTLA._nativeFormalString(\(value).formalString)"
        case .modelValue: return "SwiftTLA.TLAValue.constant(\(value).rawValue)"
        case .controlLocation:
            return switching(program.layout.controlLocations.map {
                "case .location\($0.id.ordinal): return SwiftTLA._nativeFormalString(\(String(reflecting: $0.formalName)))"
            })
        case .named(let name):
            guard let members = program.enums.cases[name] else { throw unsupported("unresolved formal enum: \(name)") }
            return switching(try members.map {
                "case .\(enumMember($0.name, of: name)): return \(try formalLiteral($0.value))"
            })
        case .finite(let members):
            return switching(try members.indices.map {
                "case .\(finiteCaseName(members, index: $0)): return \(try formalLiteral(members[$0]))"
            })
        case .union, .oneOf:
            return switching(try (type.unionAlternatives ?? []).enumerated().map {
                "case .\(unionCase(type, index: $0.offset))(let payload): return \(try formalValue("payload", type: $0.element))"
            })
        case .set(let element):
            return "try SwiftTLA.TLAStateProjection.losslessSet(\(value)) { (element) throws -> SwiftTLA.TLAValue in \(try formalValue("element", type: element)) }"
        case .array(let element):
            return "SwiftTLA.TLAValue.tuple(try \(value).map { (element) throws -> SwiftTLA.TLAValue in \(try formalValue("element", type: element)) })"
        case .tuple(let elements):
            if elements.isEmpty, elements.declaration != nil { return value + ".tlaValue" }
            let values = try elements.enumerated().map {
                try formalValue(fieldRead(value, type: type, index: $0.offset), type: $0.element)
            }
            return "SwiftTLA.TLAValue.tuple([\(values.joined(separator: ", "))])"
        case .record(let fields), .nominalRecord(_, let fields):
            let values = try fields.enumerated().map {
                ".init(\(String(reflecting: $0.element.name)), \(try formalValue(value + "." + fieldName(type, index: $0.offset), type: $0.element.type)))"
            }
            return "SwiftTLA.TLAValue.record(TLARecord([\(values.joined(separator: ", "))]))"
        case .dictionary(let key, let element):
            return """
            SwiftTLA.TLAValue.function(try \(value).reduce(into: [SwiftTLA.TLAValue: SwiftTLA.TLAValue]()) { result, entry in
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

    func formalJSONValue(_ value: String, type: CompiledValueType) throws -> String {
        let resultType = try swiftType(type)
        let invalid = "throw TLAStateProjectionDiagnostic.invalidValue(path: \"formal initial state\")"
        func decode(_ body: String) -> String {
            "try { () throws -> \(resultType) in \(body) }()"
        }
        switch type {
        case .int:
            return decode("guard case .integer(let result) = \(value) else { \(invalid) }; return result")
        case .bool:
            return decode("guard case .boolean(let result) = \(value) else { \(invalid) }; return result")
        case .string:
            return decode("guard case .string(let result) = \(value) else { \(invalid) }; return SwiftTLA._NativeString(formalString: result)")
        case .modelValue:
            return decode("guard case .string(let name) = \(value), let result = _ModelValue(rawValue: name) else { \(invalid) }; return result")
        case .named(let name):
            guard let members = program.enums.cases[name] else { throw unsupported("unresolved formal enum: \(name)") }
            let choices = try members.map { member in
                "if \(value) == \(try formalJSONLiteral(member.value)) { return .\(enumMember(member.name, of: name)) }"
            }.joined(separator: "\n")
            return decode("\(choices)\n\(invalid)")
        case .finite(let members):
            let choices = try members.enumerated().map { index, member in
                "if \(value) == \(try formalJSONLiteral(member)) { return .\(finiteCaseName(members, index: index)) }"
            }.joined(separator: "\n")
            return decode("\(choices)\n\(invalid)")
        case .set(let element):
            let member = try formalJSONValue("item", type: element)
            return decode("""
                guard case .array(let items) = \(value) else { \(invalid) }
                let members = try items.map { item in \(member) }
                let result = \(try swiftType(type))(members)
                guard result.count == members.count else { \(invalid) }
                return result
                """)
        case .array(let element):
            let member = try formalJSONValue("item", type: element)
            return decode("""
                let items: [TLAJSONValue]
                switch \(value) {
                case .array(let members): items = members
                case .object(let fields) where fields.isEmpty: items = []
                default: \(invalid)
                }
                return try items.map { item in \(member) }
                """)
        case .dictionary(let key, let element):
            // shortcut: sampled reconstruction handles integer function keys; extend for a configured non-integer key case.
            guard key == .int else { throw unsupported("formal JSON dictionary key type") }
            let member = try formalJSONValue("item", type: element)
            return decode("""
                var result: [\(nativeIntType): \(try swiftType(element))] = [:]
                switch \(value) {
                case .object(let fields):
                    for (name, item) in fields {
                        guard let key = \(nativeIntType)(name), \(nativeStringType)(key) == name else { \(invalid) }
                        guard result.updateValue(\(member), forKey: key) == nil else { \(invalid) }
                    }
                case .array(let items):
                    for (offset, item) in items.enumerated() {
                        guard result.updateValue(\(member), forKey: offset + 1) == nil else { \(invalid) }
                    }
                default: \(invalid)
                }
                return result
                """)
        case .record(let fields), .nominalRecord(_, let fields):
            let decoded = try fields.enumerated().map { index, field in
                "\(fieldName(type, index: index, escaped: false)): \(try formalJSONValue("fields[\(String(reflecting: field.name))]!", type: field.type))"
            }.joined(separator: ", ")
            let names = fields.map { String(reflecting: $0.name) }.joined(separator: ", ")
            return decode("""
                guard case .object(let fields) = \(value),
                      Set(fields.keys) == Set([\(names)]) else { \(invalid) }
                return \(resultType)(\(decoded))
                """)
        case .tuple(let elements):
            let decoded = try elements.enumerated().map { index, element in
                fieldArgument(try formalJSONValue("items[\(index)]", type: element), type: type, index: index)
            }.joined(separator: ", ")
            return decode("""
                guard case .array(let items) = \(value), items.count == \(elements.count) else { \(invalid) }
                return \(resultType)(\(decoded))
                """)
        case .unknown, .controlLocation, .union, .oneOf:
            throw unsupported("formal JSON initial value type")
        }
    }

    private func formalJSONLiteral(_ value: CompiledValue) throws -> String {
        switch try value.rendered(using: program.layout) {
        case .int(let value): return ".integer(\(value == Int.min ? "SwiftTLA._nativeIntMinimum()" : String(value)))"
        case .bool(let value): return ".boolean(\(value))"
        case .string(let value), .constant(let value): return ".string(\(String(reflecting: value)))"
        default: throw unsupported("formal JSON enum literal")
        }
    }

    func formalLiteral(_ value: CompiledValue) throws -> String {
        renderedLiteral(try value.rendered(using: program.layout))
    }

    func renderedLiteral(_ value: TLAValue) -> String {
        func emit(_ value: TLAValue) -> String {
            switch value {
            case .int(let value): return "SwiftTLA._nativeFormalInt(\(value == Int.min ? "SwiftTLA._nativeIntMinimum()" : String(value)))"
            case .bool(let value): return "SwiftTLA.TLAValue.bool(\(value))"
            case .string(let value): return "SwiftTLA._nativeFormalString(\(String(reflecting: value)))"
            case .constant(let value): return "SwiftTLA.TLAValue.constant(\(String(reflecting: value)))"
            case .set(let values): return "SwiftTLA.TLAValue.set([\(values.sorted().map(emit).joined(separator: ", "))])"
            case .tuple(let values): return "SwiftTLA.TLAValue.tuple([\(values.map(emit).joined(separator: ", "))])"
            case .record(let fields): return "SwiftTLA.TLAValue.record(TLARecord([\(fields.fields.map { ".init(\(String(reflecting: $0.name)), \(emit($0.value)))" }.joined(separator: ", "))]))"
            case .function(let values):
                let entries = values.sorted { $0.key < $1.key }.map { "\(emit($0.key)): \(emit($0.value))" }
                return "SwiftTLA.TLAValue.function([\(entries.isEmpty ? ":" : entries.joined(separator: ", "))])"
            }
        }
        return emit(value)
    }
}

extension NativeSwiftEmitter {
    private func hasConstantFunctionDomain(_ type: CompiledValueType) -> Bool {
        guard case .dictionary(.named(let name), _) = type, let cases = program.enums.cases[name], !cases.isEmpty else { return false }
        return cases.allSatisfy { if case .constant = $0.value { true } else { false } }
    }

    private func sharedProjectionDeclarations(table: DeclSyntax,
        fields: [(formalName: String, route: String, type: CompiledValueType)]) throws -> [DeclSyntax] {
        var layouts: [DeclSyntax] = []
        var functions: [(name: String, input: String, body: String)] = []
        var types: [CompiledValueType] = []
        func helper(_ type: CompiledValueType) throws -> String {
            if let index = types.firstIndex(of: type) { return "projectValue\(index)" }
            let name = "projectValue\(types.count)"
            types.append(type)
            let expression: String
            switch type {
            case .dictionary(let key, let member) where hasConstantFunctionDomain(type):
                expression = "try out.constantFunction(value, key: { key in \(try formalValue("key", type: key)) }, value: \(try helper(member)))"
            case .set(let member):
                expression = "try out.members(value, \(try helper(member)))"
            case .record(let fields), .nominalRecord(_, let fields):
                let layout = "__swifttlaProjectionRecord\(layouts.count)"
                let names = fields.map { String(reflecting: $0.name) }.joined(separator: ", ")
                layouts.append(DeclSyntax(stringLiteral: "private static let \(layout) = SwiftTLA._NativeProjectionRecord([\(names)])"))
                let cases = try fields.enumerated().map { index, field in
                    "case \(index): try \(try helper(field.type))(value.\(fieldName(type, index: index)), &child)"
                }
                expression = """
                try out.record(Self.\(layout)) { ordinal, child in
                    switch ordinal {
                    \(cases.joined(separator: "\n"))
                    default: throw SwiftTLA.TLAStateProjectionDiagnostic.invalidValue(path: "record field ordinal")
                    }
                }
                """
            case .oneOf, .union:
                let cases = try (type.unionAlternatives ?? []).enumerated().map { index, member in
                    "case .\(unionCase(type, index: index))(let item): try \(try helper(member))(item, &out)"
                }
                expression = "switch value {\n\(cases.joined(separator: "\n"))\n}"
            default:
                expression = "try out.projected(\(try formalValue("value", type: type)))"
            }
            functions.append((name, try swiftType(type), expression))
            return name
        }
        let readers = try fields.map { try helper($0.type) }
        var sinkType = "__SwiftTLAProjectionSink"
        while functions.contains(where: { $0.input.contains(sinkType) }) { sinkType += "_" }
        let helpers = functions.map {
            "func \($0.name)(_ value: \($0.input), _ out: inout \(sinkType)) throws {\n\($0.body)\n}"
        }
        let visits = fields.enumerated().map { index, field in
            "try sink.field(SwiftTLA._nativeFormalProjectionToken(Self.__swifttlaFormalProjectionTokens, at: \(index)), \(field.route), \(readers[index]))"
        }
        let walk = DeclSyntax(stringLiteral: """
        public func _visitFormalProjection<\(sinkType): SwiftTLA._NativeProjectionSink>(of snapshot: Snapshot, into sink: inout \(sinkType)) throws -> Swift.Bool {
            \(helpers.joined(separator: "\n"))
            \(visits.joined(separator: "\n"))
            return true
        }
        """)
        let projection = DeclSyntax(stringLiteral: """
        public func formalProjection(of snapshot: Snapshot) throws -> SwiftTLA.TLAStateProjection {
            var sink = SwiftTLA._NativeProjectionCollector()
            _ = try _visitFormalProjection(of: snapshot, into: &sink)
            return try sink.projection()
        }
        """)
        try verifyGeneratedFormalProjectionTokenTable(table, names: fields.map(\.formalName))
        try verifyGeneratedFormalProjectionVisits(walk, routes: fields.map(\.route), readers: readers, types: fields.map(\.type))
        return [table, projection, walk] + layouts
    }
}
