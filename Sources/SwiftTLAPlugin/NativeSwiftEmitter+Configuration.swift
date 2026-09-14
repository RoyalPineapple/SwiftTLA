import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    var machineParameters: String {
        ((program.layout.parameters.isEmpty ? [] : ["configuration: Configuration"])
            + model.api.collections.map { "\($0.swiftIdentifier) \($0.membersIdentifier): [\($0.elementType).ID]" })
            .joined(separator: ", ")
    }

    var machineArguments: String {
        ((program.layout.parameters.isEmpty ? [] : ["configuration: configuration"])
            + model.api.collections.map { "\($0.swiftIdentifier): \($0.membersIdentifier)" })
            .joined(separator: ", ")
    }

    var machineCaptures: [String] {
        (program.layout.parameters.isEmpty ? [] : ["configuration"])
            + model.api.collections.map(\.membersIdentifier)
    }

    mutating func configurationDeclarations() throws -> [DeclSyntax] {
        guard !program.layout.parameters.isEmpty else { return [] }
        let parameters = program.layout.parameters
        let inputs = Dictionary(uniqueKeysWithValues: parameters.map { ($0.binder, "_parameter\($0.binder.ordinal)") })
        let fields = try parameters.map {
            "public let `\($0.reference.name)`: \(try swiftType(program.bindingTypes[$0.binder]!))"
        }.joined(separator: "\n")
        let arguments = try parameters.map {
            "`\($0.reference.name)` \(inputs[$0.binder]!): \(try swiftType(program.bindingTypes[$0.binder]!))"
        }.joined(separator: ", ")
        var body: [String] = []
        for parameter in parameters {
            guard let domain = program.behavior.parameterDomains[parameter.binder] else {
                throw unsupported("missing parameter domain: \(parameter.reference.name)")
            }
            let value = inputs[parameter.binder]!
            let domainName = "_domain\(parameter.binder.ordinal)"
            body.append("let \(domainName) = \(try expression(domain, state: "", substitutions: inputs))")
            body.append("""
            guard \(domainName).contains(\(value)) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: \(String(reflecting: "configuration." + parameter.reference.name)),
                    expected: String(describing: \(domainName)), actual: String(describing: \(value)))
            }
            self.`\(parameter.reference.name)` = \(value)
            """)
        }
        return try nativeDeclarations("""
        public struct Configuration: Hashable, Sendable {
            \(fields)
            public init(\(arguments)) throws {
                \(body.joined(separator: "\n"))
            }
        }
        public let configuration: Configuration
        """)
    }
}
