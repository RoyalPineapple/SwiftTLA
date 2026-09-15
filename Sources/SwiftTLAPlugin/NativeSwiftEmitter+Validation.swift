import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    mutating func validationDeclarations() throws -> [DeclSyntax] {
        guard !program.behavior.validationScenarios.isEmpty else { return [] }
        guard model.api.collections.isEmpty else {
            throw unsupported("validation scenarios require explicit collection bindings")
        }
        guard program.refinements.isEmpty else {
            throw unsupported("validation scenarios require resolved refinement expectation handles")
        }
        let properties = (program.behavior.invariants + program.behavior.reachabilityProperties).map { (id: $0.id, name: $0.name) }
            + program.behavior.temporalProperties.map { (id: $0.id, name: $0.name) }
        let identifiers = GeneratedMachineAPI.generatedIdentifiers(properties.map(\.name), fallback: "property")
        let propertyCases = zip(properties, identifiers).map {
            "case \($0.1) = \(String(reflecting: $0.0.name))"
        }.joined(separator: "\n")
        let hasConfiguration = !program.layout.parameters.isEmpty
        var scenarios: [String] = []
        for scenario in program.behavior.validationScenarios {
            let bindings = try program.layout.parameters.map { parameter in
                guard let value = scenario.bindings[parameter.binder] else {
                    throw unsupported("missing scenario binding: \(parameter.reference.name)")
                }
                return "\(parameter.reference.name): \(try expression(value, state: ""))"
            }.joined(separator: ", ")
            let expectations = zip(properties, identifiers).map { property, identifier in
                ".\(identifier): .\((scenario.expectations[property.id] ?? .satisfied).rawValue)"
            }.joined(separator: ", ")
            let deadlock = program.behavior.checkDeadlock
                ? ".\((scenario.deadlockExpectation ?? .satisfied).rawValue)" : "nil"
            scenarios.append("""
            ValidationScenario(name: \(String(reflecting: scenario.name)),
                \(hasConfiguration ? "configuration: try Configuration(\(bindings))," : "")
                expectations: [\(properties.isEmpty ? ":" : expectations)],
                deadlockExpectation: \(deadlock))
            """)
        }
        let arguments = hasConfiguration ? "configuration: configuration" : ""
        return try nativeDeclarations("""
        \(properties.isEmpty ? "public enum Property: Hashable, Sendable {}" : "public enum Property: String, CaseIterable, Sendable {\n\(propertyCases)\n}")
        public struct ValidationScenario: ModelValidationScenario {
            public typealias Machine = \(model.typeName)
            public typealias Property = \(model.typeName).Property
            public let name: String
            \(hasConfiguration ? "public let configuration: Configuration" : "")
            public let expectations: [Property: ValidationExpectation]
            public let deadlockExpectation: ValidationExpectation?

            public func initialMachines() throws -> [\(model.typeName)] {
                try \(model.typeName).initialMachines(\(arguments))
            }
            public var formalPropertyNames: [Property: String] {
                \(properties.isEmpty ? "[:]" : "Dictionary(uniqueKeysWithValues: Property.allCases.map { ($0, $0.rawValue) })")
            }
            public func render() throws -> RenderedSpecification {
                try \(model.typeName).render(\(arguments))
            }
        }
        public static func validationScenarios() throws -> [ValidationScenario] {
            [\(scenarios.joined(separator: ",\n"))]
        }
        """)
    }
}
