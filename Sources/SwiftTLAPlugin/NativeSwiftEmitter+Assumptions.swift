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
        declarations += try valueTypeDeclarations()
        let configured = !program.layout.parameters.isEmpty
        let parameterArgument = configured ? "configuration: Configuration" : ""
        let parameterCall = configured ? "configuration: configuration" : ""
        let substitutions = Dictionary(uniqueKeysWithValues: program.layout.parameters.map {
            ($0.binder, "configuration.`\($0.reference.name)`")
        })
        printTOutputName = "_evaluatedValues"
        defer { printTOutputName = nil }
        let assumptionExpression = try expression(assumption.expression, state: "", substitutions: substitutions)
        var pending = [assumption.expression]
        var recordsOutput = false
        while let candidate = pending.popLast() {
            if case .printT = candidate.operation { recordsOutput = true; break }
            pending.append(contentsOf: candidate.children)
        }
        declarations += try nativeDeclarations("""
        public static func evaluateAssumptions(\(parameterArgument)) throws -> AssumptionEvaluation {
            \(recordsOutput ? "var" : "let") _evaluatedValues: [TLAValue] = []
            let satisfied = \(assumptionExpression)
            return AssumptionEvaluation(
                satisfied: satisfied,
                evaluatedValues: _evaluatedValues)
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
            return "ValidationScenario(name: \(String(reflecting: scenario.name)), displayName: \(String(reflecting: scenario.displayLabel ?? scenario.name))\(configured ? ", configuration: try Configuration(\(bindings))" : ""))"
        }
        declarations += try nativeDeclarations("""
        public struct ValidationScenario: AssumptionValidationScenario {
            public let name: String
            public let displayName: String
            \(configured ? "public let configuration: Configuration" : "")
            public func evaluateAssumptions() throws -> AssumptionEvaluation {
                try \(model.typeName).evaluateAssumptions(\(parameterCall))
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
