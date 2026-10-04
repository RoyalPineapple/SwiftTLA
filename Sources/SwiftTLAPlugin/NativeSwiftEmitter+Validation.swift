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
            let symmetry = scenario.symmetry.map { String(reflecting: "Symm\($0.variableName)") } ?? "nil"
            let profileName = scenario.fairnessProfileIndex.map {
                String(reflecting: program.behavior.fairnessProfiles[$0].name)
            } ?? "nil"
            scenarios.append("""
            ValidationScenario(name: \(String(reflecting: scenario.name)),
                displayName: \(String(reflecting: scenario.displayLabel ?? scenario.name)),
                \(hasConfiguration ? "configuration: try Configuration(\(bindings))," : "")
                checking: ModelChecks(properties: [\(selected.map { ".\($0.1)" }.joined(separator: ", "))], checkDeadlock: \(scenario.checkDeadlock)),
                checkingMode: .\(scenario.checkingMode.rawValue),
                behavior: .\(scenario.behavior.rawValue),
                selectedSymmetry: \(symmetry),
                selectedFairnessProfile: \(scenario.fairnessProfileIndex.map(String.init) ?? "nil"),
                selectedFairnessProfileName: \(profileName),
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
            public let displayName: String
            \(hasConfiguration ? "public let configuration: Configuration" : "")
            public let checking: ModelChecks<Property>
            public let checkingMode: ValidationCheckingMode
            public let behavior: ModelBehavior
            let selectedSymmetry: String?
            let selectedFairnessProfile: Int?
            let selectedFairnessProfileName: String?
            public let expectations: [Property: ValidationExpectation]
            public let deadlockExpectation: ValidationExpectation?

            public func initialMachines() throws -> [\(model.typeName)] {
                try \(model.typeName).initialMachines(\(arguments))
            }
            public var formalPropertyNames: [Property: String] {
                Machine.formalPropertyNames
            }
            public func fairnessConditions(on machine: Machine) throws -> [MachineFairnessCondition<Machine.Snapshot, Machine.Action>] {
                switch selectedFairnessProfile {
                \(program.behavior.fairnessProfiles.indices.map { index in
                    "case \(index): return try machine._fairnessProfile\(index)Conditions()"
                }.joined(separator: "\n"))
                case nil: return try machine.fairnessConditions()
                default: throw ExplorationError.configurationMismatch
                }
            }
            public func render() throws -> RenderedSpecification {
                try \(model.typeName).render(\(arguments)).selectingChecks(checking,
                    formalPropertyNames: Machine.formalPropertyNames, behavior: behavior,
                    symmetry: selectedSymmetry, fairnessProfile: selectedFairnessProfileName)
            }
        }
        public static func validationScenarios() throws -> [ValidationScenario] {
            [\(scenarios.joined(separator: ",\n"))]
        }
        """)
    }
}
