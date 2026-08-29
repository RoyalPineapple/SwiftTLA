public enum AlgorithmDiagnosticCode: String, Sendable, Hashable {
    case reservedName
    case invalidName
    case emptyDomain
    case duplicateDomainMember
    case duplicateLabel
    case invalidTarget
    case duplicateRootWrite
    case invalidAtomicControlFlow
    case missingStop
    case invalidAlgorithmComponent
    case invalidSequentialFairness
    case duplicateProcedure
    case duplicateProcedureVariable
    case invalidProcedureTarget
    case invalidProcedureArity
    case invalidProcedureReturn
    case invalidProcedureControlFlow
    case statementMacroArgumentCount
    case statementMacroAssignmentTarget
}

public enum AlgorithmDiagnosticAnchor: Sendable, Hashable {
    case algorithm
    case process(Int)
    case step(process: Int, label: String)
}

public struct AlgorithmDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    public let code: AlgorithmDiagnosticCode
    public let anchor: AlgorithmDiagnosticAnchor

    init(_ code: AlgorithmDiagnosticCode, at anchor: AlgorithmDiagnosticAnchor) {
        self.code = code
        self.anchor = anchor
    }

    public var description: String {
        "\(code.rawValue) at \(anchor)"
    }
}

public struct AlgorithmValidationError: Error, Sendable, Hashable {
    public let diagnostics: [AlgorithmDiagnostic]

    init(_ diagnostics: [AlgorithmDiagnostic]) {
        self.diagnostics = diagnostics
    }
}

internal enum AlgorithmPlacementValidator {
    static func validate(_ model: AlgorithmModel) throws {
        for (index, component) in model.components.enumerated() {
            try validate(component, path: ["algorithm", "components[\(index)]"])
        }
    }

    private static func validate(
        _ component: AlgorithmComponentModel,
        path: [String]
    ) throws {
        switch component {
        case .invalidPlacement(let component):
            throw diagnostic(for: component, path: path)
        case .process(let process):
            for (index, component) in process.components.enumerated() {
                try validate(component, path: path + ["components[\(index)]"])
            }
        case .procedure(let procedure):
            for (index, component) in procedure.components.enumerated() {
                try validate(component, path: path + ["procedure", "components[\(index)]"])
            }
        case .shared, .invariant, .temporal, .formalOperator,
             .stateConstraint, .local, .step:
            return
        }
    }

    private static func diagnostic(
        for component: InvalidAlgorithmComponent,
        path: [String]
    ) -> CompilationDiagnostic {
        switch component {
        case .genericFairness:
            .init(
                code: .invalidAlgorithmFairnessPlacement,
                stage: .validation,
                path: path.joined(separator: "."),
                expected: component.expectedPlacement,
                actual: component.actualPlacement,
                nextSafeAction: component.nextSafeAction
            )
        case .assumption:
            .init(
                code: .invalidAlgorithmAssumptionPlacement,
                stage: .validation,
                path: path.joined(separator: "."),
                expected: component.expectedPlacement,
                actual: component.actualPlacement,
                nextSafeAction: component.nextSafeAction
            )
        }
    }
}
