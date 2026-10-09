import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    var machineParameters: String {
        program.layout.parameters.isEmpty ? "" : "configuration: Configuration"
    }

    var machineArguments: String {
        program.layout.parameters.isEmpty ? "" : "configuration: configuration"
    }

    var machineCaptures: [String] {
        program.layout.parameters.isEmpty ? [] : ["configuration"]
    }

    mutating func configurationDeclarations(includeStoredConfiguration: Bool = true) throws -> [DeclSyntax] {
        guard !program.layout.parameters.isEmpty else { return [] }
        let parameters = program.layout.parameters
        let inputs = Dictionary(uniqueKeysWithValues: parameters.map { ($0.binder, "_parameter\($0.binder.ordinal)") })
        let fields = try parameters.map {
            "public let `\($0.reference.name)`: \(try swiftType(program.bindingTypes[$0.binder]!))"
        }.joined(separator: "\n")
        let arguments = try parameters.map {
            "`\($0.reference.name)` \(inputs[$0.binder]!): \(try swiftType(program.bindingTypes[$0.binder]!))"
        }.joined(separator: ", ")
        let displayNames = parameters.map {
            "\\Configuration.`\($0.reference.name)`: \(String(reflecting: $0.reference.displayLabel ?? $0.reference.name))"
        }.joined(separator: ",\n")
        let formalNames = parameters.map {
            "\\Configuration.`\($0.reference.name)`: .init(swiftName: \(String(reflecting: $0.reference.name)), formalName: \(String(reflecting: $0.reference.name)))"
        }.joined(separator: ",\n")
        var body: [String] = []
        for parameter in parameters {
            guard let domain = program.behavior.parameterDomains[parameter.binder] else {
                throw unsupported("missing parameter domain: \(parameter.reference.name)")
            }
            let value = inputs[parameter.binder]!
            let membership = CompiledExpression(operation: .in, resultType: .bool, children: [
                CompiledExpression(operation: .boundValue(parameter.binder),
                    resultType: program.bindingTypes[parameter.binder]!, children: []),
                domain
            ])
            body.append("""
            guard \(try expression(membership, state: "", substitutions: inputs)) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: \(String(reflecting: "configuration." + parameter.reference.name)),
                    expected: "a member of the declared parameter domain", actual: String(describing: \(value)))
            }
            self.`\(parameter.reference.name)` = \(value)
            """)
        }
        return try nativeDeclarations("""
        public struct Configuration: Hashable, GeneratedModelFields {
            \(fields)
            public static var displayNames: [PartialKeyPath<Configuration>: String] {
                [\(displayNames)]
            }
            public static var fieldIdentities: [PartialKeyPath<Configuration>: GeneratedModelFieldIdentity] {
                [\(formalNames)]
            }
            public init(\(arguments)) throws {
                \(body.joined(separator: "\n"))
            }
        }
        \(includeStoredConfiguration ? "public let configuration: Configuration" : "")
        """)
    }
}
