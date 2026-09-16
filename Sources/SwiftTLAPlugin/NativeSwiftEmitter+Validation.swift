import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    func propertyIdentityDeclarations() throws -> [DeclSyntax] {
        let properties = program.layout.properties
        let names = properties.map { $0.declaration.name }
        let identifiers = properties.map { propertyCases[$0.id]! }
        let cases = identifiers.map { "case \($0)" }.joined(separator: "\n")
        let projections = zip(identifiers, names).map {
            ".\($0.0): \(String(reflecting: $0.1))"
        }.joined(separator: ",\n")
        let displayNames = properties.map { program.layout.propertyDisplayName($0.id) ?? $0.declaration.name }
        let displayProjections = zip(identifiers, displayNames).map {
            ".\($0.0): \(String(reflecting: $0.1))"
        }.joined(separator: ",\n")
        return try nativeDeclarations("""
        public enum Property: Hashable, CaseIterable, Sendable {
            \(cases)
        }
        public static var formalPropertyNames: [Property: String] {
            [\(identifiers.isEmpty ? ":" : projections)]
        }
        public static var propertyDisplayNames: [Property: String] {
            [\(identifiers.isEmpty ? ":" : displayProjections)]
        }
        """)
    }

    mutating func validationDeclarations() throws -> [DeclSyntax] {
        guard !program.behavior.validationScenarios.isEmpty else { return [] }
        guard model.api.collections.isEmpty else {
            throw unsupported("validation scenarios require explicit collection bindings")
        }
        let properties = program.layout.properties
        let identifiers = properties.map { propertyCases[$0.id]! }
        let hasConfiguration = !program.layout.parameters.isEmpty
        var scenarios: [String] = []
        for scenario in program.behavior.validationScenarios {
            let bindings = try program.layout.parameters.map { parameter in
                guard let value = scenario.bindings[parameter.binder] else {
                    throw unsupported("missing scenario binding: \(parameter.reference.name)")
                }
                return "\(parameter.reference.name): \(try expression(value, state: ""))"
            }.joined(separator: ", ")
            let selected = zip(properties, identifiers).filter { scenario.checks.contains($0.0.id) }
            let expectations = selected.map { property, identifier in
                ".\(identifier): .\((scenario.expectations[property.id] ?? .satisfied).rawValue)"
            }.joined(separator: ", ")
            let deadlock = scenario.checkDeadlock
                ? ".\((scenario.deadlockExpectation ?? .satisfied).rawValue)" : "nil"
            scenarios.append("""
            ValidationScenario(name: \(String(reflecting: scenario.name)),
                \(hasConfiguration ? "configuration: try Configuration(\(bindings))," : "")
                checking: ModelChecks(properties: [\(selected.map { ".\($0.1)" }.joined(separator: ", "))], checkDeadlock: \(scenario.checkDeadlock)),
                behavior: .\(scenario.behavior.rawValue),
                expectations: [\(selected.isEmpty ? ":" : expectations)],
                deadlockExpectation: \(deadlock))
            """)
        }
        let arguments = hasConfiguration ? "configuration: configuration" : ""
        return try nativeDeclarations("""
        public struct ValidationScenario: ModelValidationScenario {
            public typealias Machine = \(model.typeName)
            public typealias Property = \(model.typeName).Property
            public let name: String
            \(hasConfiguration ? "public let configuration: Configuration" : "")
            public let checking: ModelChecks<Property>
            public let behavior: ModelBehavior
            public let expectations: [Property: ValidationExpectation]
            public let deadlockExpectation: ValidationExpectation?

            public func initialMachines() throws -> [\(model.typeName)] {
                try \(model.typeName).initialMachines(\(arguments))
            }
            public var formalPropertyNames: [Property: String] {
                Machine.formalPropertyNames
            }
            public func render() throws -> RenderedSpecification {
                try \(model.typeName).render(\(arguments)).selectingChecks(checking, formalPropertyNames: Machine.formalPropertyNames, behavior: behavior)
            }
        }
        public static func validationScenarios() throws -> [ValidationScenario] {
            [\(scenarios.joined(separator: ",\n"))]
        }
        """)
    }
}
