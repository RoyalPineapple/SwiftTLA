import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin

@Suite("Specification source authority")
struct SpecificationSourceAuthorityTests {
    @Test("Direct specification getters retain their inline declaration")
    func directGettersAreAdmitted() throws {
        let getters = [
            "#spec(\"Authority\") {}",
            "return #spec(\"Authority\") {}",
            "get { #spec(\"Authority\") {} }",
            "get { return TLASpec(\"Authority\") {} }",
            "TLASpec(\"Authority\", {})",
            "TLASpec(\"Authority\", scoped: { scope in })",
            "#spec(\"Authority\", scoped: { scope in })"
        ]
        for getter in getters {
            let declaration = try declaration("static var spec: TLASpec { \(getter) }")
            let source = try #require(TLASpecVerifier.findSpec(in: declaration.memberBlock.members))
            #expect(source.name == "Authority")
        }
    }

    @Test("Runtime getter statements cannot change the compiled declaration")
    func executableGettersAreRejected() throws {
        let getters = [
            "recordAccess(); return #spec(\"Authority\") {}",
            "if dynamicFlag { return otherSpec }; return #spec(\"Authority\") {}",
            "return #spec(\"Authority\") {}; recordAccess()",
            "defer { recordAccess() }; return TLASpec(\"Authority\") {}",
            "let ignored = makeValue(); TLASpec(\"Authority\") {}",
            "get { recordAccess(); return TLASpec(\"Authority\") {} }",
            "get { TLASpec(\"Authority\") {} } set { recordAccess() }",
            "get async { TLASpec(\"Authority\") {} }",
            "dynamicFlag ? otherSpec : TLASpec(\"Authority\") {}",
            "TLASpec(\"Authority\", makeBuilder())",
            "TLASpec(\"Authority\", ignored: makeValue()) {}",
            "#spec(\"Authority\", ignored: makeValue()) {}",
            "TLASpec(\"Authority\") {} ignored: {}"
        ]
        for getter in getters {
            try expectRejection("static var spec: TLASpec { \(getter) }")
        }
    }

    @Test("Specification identity requires one static getter declaration")
    func alternateStorageIsRejected() throws {
        for members in [
            "var spec: TLASpec { TLASpec(\"Authority\") {} }",
            "static let spec = TLASpec(\"Authority\") {}",
            "static var spec: TLASpec { TLASpec(\"Authority\") {} }; static var spec: TLASpec { TLASpec(\"Other\") {} }"
        ] {
            try expectRejection(members)
        }
    }

    @Test("Finite domains preserve every admitted case and empty domain")
    func literalEnumDomainsArePreserved() throws {
        for (initializer, count) in [("[.second, Self.first]", 2), ("[]", 0), ("allCases", 2)] {
            let declaration = try declaration("""
            enum Phase: String, CaseIterable, FiniteTLAValueDomain {
                case first, second
                static let finiteValues: [Self] = \(initializer)
            }
            """)
            let enums = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            let domain = try #require(enums.first?.formalDomainValues)
            #expect(domain.count == count)
        }
    }

    @Test("Dynamic or partially parsed finite domains cannot silently become all cases")
    func dynamicEnumDomainsAreRejected() throws {
        for member in [
            "static let finiteValues = makeDomain()",
            "static var finiteValues: [Self] { [.first] }",
            "static var finiteValues: [Self] = [.first]",
            "static let finiteValues = [.first, makeCase()]",
            "static let finiteValues = [Other.first]",
            "static let finiteValues = Other.allCases",
            "static let allCases: [Self] = [.first]; static let finiteValues = allCases"
        ] {
            let declaration = try declaration("""
            enum Phase: String, CaseIterable, FiniteTLAValueDomain {
                case first, second
                \(member)
            }
            """)
            #expect(throws: ModelMacroError.dynamicFiniteDomain(typeName: "Phase")) {
                _ = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            }
        }
    }

    @Test("Explicit enum encodings preserve formal atoms and primitive raw values")
    func explicitEnumEncodingsArePreserved() throws {
        for body in [".constant(rawValue)", "return TLAValue.constant(self.rawValue)", "get { .constant(rawValue) }"] {
            let declaration = try declaration("""
            enum Key: String, CaseIterable, FiniteTLAValueDomain {
                case first = "k1", second = "k2"
                var tlaValue: TLAValue { \(body) }
                static let finiteValues: [Self] = [.second]
            }
            """)
            let info = try #require(TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members).first)
            #expect(info.cases.map(\.value) == [.constant("k1"), .constant("k2")])
            #expect(info.formalDomainValues == [.constant("k2")])
        }
        let strings = try declaration("""
        enum Key: String, TLAValueType {
            case first = "k1"
            var tlaValue: TLAValue { .string(rawValue) }
        }
        """)
        #expect(try TLASpecVerifier.collectEnumVariables(from: strings.memberBlock.members).first?.cases.first?.value == .string("k1"))
        let integers = try declaration("""
        enum Key: Int, TLAValueType {
            case first = 4
            var tlaValue: TLAValue { .int(rawValue) }
        }
        """)
        #expect(try TLASpecVerifier.collectEnumVariables(from: integers.memberBlock.members).first?.cases.first?.value == .int(4))
    }

    @Test("A final maximum integer enum case does not overflow macro expansion")
    func maximumIntegerEnumCasesAreAdmitted() throws {
        for cases in ["case maximum = 9223372036854775807", "case previous = 9223372036854775806, maximum"] {
            let declaration = try declaration("enum Limit: Int, TLAValueType { \(cases) }")
            let info = try #require(TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members).first)
            #expect(info.cases.last?.value == .int(Int.max))
        }
        let declaration = try declaration("enum Limit: Int, TLAValueType { case maximum = 9223372036854775807, overflow }")
        #expect(throws: ModelMacroError.invalidEnumRawValue(caseName: "overflow")) {
            _ = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
        }
    }

    @Test("Escaped enum cases retain semantic names and default raw values")
    func escapedEnumCasesPreserveIdentity() throws {
        let declaration = try declaration("""
        enum Step: String, CaseIterable {
            case `repeat`, normal
            static let finiteValues: [Self] = [Self.`repeat`]
        }
        """)
        let info = try #require(TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members).first)
        #expect(info.cases.map(\.name) == ["repeat", "normal"])
        #expect(info.cases.map(\.value) == [.string("repeat"), .string("normal")])
        #expect(info.formalDomainValues == [.string("repeat")])
    }

    @Test("Dynamic enum encodings cannot silently change generated semantics")
    func dynamicEnumEncodingsAreRejected() throws {
        for body in [
            "encode(rawValue)",
            "recordAccess(); return .constant(rawValue)",
            "flag ? .constant(rawValue) : .string(rawValue)",
            #".constant("different")"#,
            ".int(rawValue)",
            "get { .constant(rawValue) } set { recordAccess() }"
        ] {
            let declaration = try declaration("""
            enum Key: String, TLAValueType {
                case first
                var tlaValue: TLAValue { \(body) }
            }
            """)
            #expect(throws: ModelMacroError.unsupportedEnumEncoding(typeName: "Key")) {
                _ = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            }
        }
    }

    @Test("Native source metadata preserves aliases and formal record field names")
    func sourceMetadataPreservesAliasesAndRecordNames() throws {
        let declaration = try declaration(#"""
        typealias Value = OneOf<Transaction, NoValue>
        struct OperationFields {
            let operation: OperationKind
            let value: Value
        }
        enum OperationSchema: TLARecordSchema {
            typealias Fields = OperationFields
            static func fieldName<Value>(for field: KeyPath<OperationFields, Value>) -> String? {
                let key = field as AnyKeyPath
                if key == \OperationFields.operation { return "op" }
                if key == \OperationFields.value { return "value" }
                return nil
            }
            static let operation = field(\OperationFields.operation)
            static let value = field(\OperationFields.value)
            static let fields = [
                TLARecordFieldDeclaration(operation, default: OperationKind.read),
                TLARecordFieldDeclaration(value, default: Value.second(.noVal))
            ]
        }
        """#)
        let metadata = try TLASpecVerifier.sourceTypes(in: declaration.memberBlock.members, enums: [])
        #expect(metadata.aliases["Value"] == "OneOf<Transaction, NoValue>")
        #expect(metadata.records["OperationSchema"]?.map(\.name) == ["op", "value"])
        #expect(metadata.records["OperationSchema"]?.map(\.sourceName) == ["operation", "value"])
        #expect(metadata.records["OperationSchema"]?.map(\.swiftType) == ["OperationKind", "Value"])
    }

    @Test("Dynamic schema field-name mappings are rejected")
    func sourceMetadataRejectsDynamicRecordNames() throws {
        let declaration = try declaration(#"""
        struct DynamicFields { let value: Int }
        enum Schema: TLARecordSchema {
            typealias Fields = DynamicFields
            static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String? {
                return runtimeName(field)
            }
        }
        """#)
        #expect(throws: ModelMacroError.unsupportedRecordSchema(typeName: "Schema")) {
            _ = try TLASpecVerifier.sourceTypes(in: declaration.memberBlock.members, enums: [])
        }
    }

    private func expectRejection(_ members: String) throws {
        let declaration = try declaration(members)
        #expect(throws: ModelMacroError.nonLiteralSpecification) {
            _ = try TLASpecVerifier.findSpec(in: declaration.memberBlock.members)
        }
    }

    private func declaration(_ members: String) throws -> StructDeclSyntax {
        try #require(Parser.parse(source: "struct Model { \(members) }")
            .statements.first?.item.as(StructDeclSyntax.self))
    }
}
