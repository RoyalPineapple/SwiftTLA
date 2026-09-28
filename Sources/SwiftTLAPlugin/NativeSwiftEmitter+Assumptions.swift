import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    mutating func assumptionMembers() throws -> [DeclSyntax] {
        guard program.layout.variables.isEmpty, program.behavior.actions.isEmpty,
              program.behavior.invariants.isEmpty, program.behavior.reachabilityProperties.isEmpty,
              program.behavior.temporalProperties.isEmpty, program.refinements.isEmpty,
              program.behavior.constraint == nil, program.behavior.fairness.isEmpty,
              let assumption = program.behavior.assume else {
            throw unsupported("assumption-only module with no state, actions, or selected state checks")
        }
        var declarations = try configurationDeclarations(includeStoredConfiguration: false)
        let configured = !program.layout.parameters.isEmpty
        let parameterArgument = configured ? "configuration: Configuration" : ""
        let parameterCall = configured ? "configuration: configuration" : ""
        let substitutions = Dictionary(uniqueKeysWithValues: program.layout.parameters.map {
            ($0.binder, "configuration.`\($0.reference.name)`")
        })
        declarations += try nativeDeclarations("""
        public static func checkAssumptions(\(parameterArgument)) throws -> Bool {
            return \(try expression(assumption.expression, state: "", substitutions: substitutions))
        }
        """)
        let scenarios = try program.behavior.validationScenarios.map { scenario -> String in
            guard scenario.checks.isEmpty, !scenario.checkDeadlock,
                  scenario.expectations.isEmpty, scenario.deadlockExpectation == nil else {
                throw unsupported("assumption-only validation cannot select state or deadlock checks")
            }
            let bindings = try program.layout.parameters.map { parameter -> String in
                guard let value = scenario.bindings[parameter.binder] else {
                    throw unsupported("missing assumption scenario binding: \(parameter.reference.name)")
                }
                return "\(parameter.reference.name): \(try expression(value, state: ""))"
            }.joined(separator: ", ")
            return "ValidationScenario(name: \(String(reflecting: scenario.name))\(configured ? ", configuration: try Configuration(\(bindings))" : ""))"
        }
        declarations += try nativeDeclarations("""
        public struct ValidationScenario: AssumptionValidationScenario {
            public let name: String
            \(configured ? "public let configuration: Configuration" : "")
            public func checkAssumptions() throws -> Bool {
                try \(model.typeName).checkAssumptions(\(parameterCall))
            }
            public func render() throws -> RenderedSpecification {
                try \(model.typeName).render(\(parameterCall))
            }
        }
        public static func validationScenarios() throws -> [ValidationScenario] {
            [\(scenarios.joined(separator: ",\n"))]
        }
        """)
        declarations += try exportDeclarations()
        return declarations
    }
}
