import SwiftSyntax
import SwiftParser
import SwiftTLA

extension NativeSwiftEmitter {
    /// Serialize resolved native values only at the independent validation boundary.
    func formalProjectionDeclarations() throws -> [DeclSyntax] {
        let fields = try program.layout.variables.map { variable in
            let name = variable.declaration.name
            guard TLAStateProjection.Token(validating: name) != nil else {
                throw unsupported("invalid formal state identifier: \(name)")
            }
            let route = stateValue(variable.id, prefix: "snapshot.")
            return (formalName: name, route: route,
                value: try formalValue(route, type: program.variableTypes[variable.id]!))
        }
        let tokens = fields.map { field in
            "TLAStateProjection.Token(validating: \(String(reflecting: field.formalName)))!"
        }.joined(separator: ", ")
        let entries = fields.enumerated().map { index, field in
            ".init(token: Self.__swifttlaFormalProjectionTokens[\(index)], value: \(field.value))"
        }.joined(separator: ",\n")
        let declarations = [DeclSyntax(stringLiteral: """
        private static let __swifttlaFormalProjectionTokens: [TLAStateProjection.Token] = [\(tokens)]
        """), DeclSyntax(stringLiteral: """
        public func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection {
            try TLAStateProjection(validating: [\(entries)])
        }
        """)]
        try verifyGeneratedFormalProjectionOutput(declarations, fields: fields)
        return declarations
    }

    func formalValue(_ value: String, type: CompiledValueType) throws -> String {
        func switching(_ cases: [String]) -> String {
            "try { () throws -> TLAValue in switch \(value) {\n\(cases.joined(separator: "\n"))\n} }()"
        }
        switch type {
        case .int: return "TLAValue.int(\(value))"
        case .bool: return "TLAValue.bool(\(value))"
        case .string: return "TLAValue.canonicalSwiftString(\(value))"
        case .modelValue: return "TLAValue.constant(\(value).rawValue)"
        case .controlLocation:
            return switching(program.layout.controlLocations.map {
                "case .location\($0.id.ordinal): return .string(\(String(reflecting: $0.formalName)))"
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
        case .union, .oneOf:
            return switching(try (type.unionAlternatives ?? []).enumerated().map {
                "case .\(unionCase(type, index: $0.offset))(let payload): return \(try formalValue("payload", type: $0.element))"
            })
        case .set(let element):
            return "try TLAStateProjection.losslessSet(\(value)) { (element) throws -> TLAValue in \(try formalValue("element", type: element)) }"
        case .array(let element):
            return "TLAValue.tuple(try \(value).map { (element) throws -> TLAValue in \(try formalValue("element", type: element)) })"
        case .tuple(let elements):
            let values = try elements.enumerated().map {
                try formalValue(value + "." + fieldName(type, index: $0.offset), type: $0.element)
            }
            return "TLAValue.tuple([\(values.joined(separator: ", "))])"
        case .record(let fields), .nominalRecord(_, let fields):
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
            return decode("guard case .string(let result) = \(value) else { \(invalid) }; return result")
        case .modelValue:
            return decode("guard case .string(let name) = \(value), let result = _ModelValue(rawValue: name) else { \(invalid) }; return result")
        case .named(let name):
            guard let members = program.enums.cases[name] else { throw unsupported("unresolved formal enum: \(name)") }
            let choices = try members.map { member in
                "if \(value) == \(try formalJSONLiteral(member.value)) { return .`\(member.name)` }"
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
                let result = Set(members)
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
                var result: [Int: \(try swiftType(element))] = [:]
                switch \(value) {
                case .object(let fields):
                    for (name, item) in fields {
                        guard let key = Int(name), String(key) == name else { \(invalid) }
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
                "\(fieldName(type, index: index)): \(try formalJSONValue("items[\(index)]", type: element))"
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
        case .int(let value): return ".integer(\(value == Int.min ? "Int.min" : String(value)))"
        case .bool(let value): return ".boolean(\(value))"
        case .string(let value), .constant(let value): return ".string(\(String(reflecting: value)))"
        default: throw unsupported("formal JSON enum literal")
        }
    }

    private func formalLiteral(_ value: CompiledValue) throws -> String {
        renderedLiteral(try value.rendered(using: program.layout))
    }

    func renderedLiteral(_ value: TLAValue) -> String {
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
        return emit(value)
    }
}

func verifyGeneratedFormalProjectionOutput(
    _ declarations: [DeclSyntax], fields: [(formalName: String, route: String, value: String)]
) throws {
    func tokens(_ syntax: some SyntaxProtocol) -> [String] {
        Array(syntax.tokens(viewMode: .sourceAccurate)).map(\.text)
    }
    func reject(_ reason: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.formalProjection",
            expected: "one ordered formal entry from each complete snapshot field",
            actual: reason,
            nextSafeAction: "Report this native code generation failure."
        )
    }
    let tokenValues = fields.map {
        "TLAStateProjection.Token(validating: \(String(reflecting: $0.formalName)))!"
    }.joined(separator: ", ")
    let expectedTokens = Parser.parse(source: """
    private static let __swifttlaFormalProjectionTokens: [TLAStateProjection.Token] = [\(tokenValues)]
    """).statements.first?.item
    guard declarations.count == 2, let expectedTokens,
          tokens(declarations[0]) == tokens(expectedTokens) else {
        throw reject("the formal state token list differs from the compiled variable names")
    }
    for field in fields {
        let expectedRoute = Parser.parse(source: field.route).statements.first?.item
        let value = Parser.parse(source: field.value).statements.first?.item
        guard let expectedRoute, let value else { throw reject("the projected value cannot be parsed") }
        let route = tokens(expectedRoute)
        let valueTokens = tokens(value)
        let references = valueTokens.indices.filter { valueTokens[$0] == "snapshot" }
        guard !references.isEmpty, references.allSatisfy({ index in
            index + route.count <= valueTokens.count
                && Array(valueTokens[index..<(index + route.count)]) == route
        }) else { throw reject("the projected value for \(field.formalName) reads a different snapshot field") }
    }
    let expectedEntries = fields.enumerated().map { index, field in
        ".init(token: Self.__swifttlaFormalProjectionTokens[\(index)], value: \(field.value))"
    }.joined(separator: ",\n")
    let expectedFunction = Parser.parse(source: """
    public func formalProjection(of snapshot: Snapshot) throws -> TLAStateProjection {
        try TLAStateProjection(validating: [\(expectedEntries)])
    }
    """).statements.first?.item
    guard let expectedFunction, tokens(declarations[1]) == tokens(expectedFunction) else {
        throw reject("the projection call shape or formal token ordering differs from the checked rule")
    }
}
