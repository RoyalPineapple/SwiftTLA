public enum AlgorithmDiagnosticCode: String, Sendable, Hashable {
    case reservedName
    case invalidName
    case emptyDomain
    case duplicateDomainMember
    case duplicateLabel
    case invalidTarget
    case duplicateRootWrite
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

internal enum AlgorithmCapabilityValidator {
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
        case .unsupported(let construct):
            throw diagnostic(for: construct, path: path)
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
        for construct: DeclaredLanguageConstruct,
        path: [String]
    ) -> LanguageCapabilityDiagnostic {
        let capability = LanguageCapabilityLedger.capability(for: construct)
        return .init(
            code: .unsupportedConstruct,
            construct: .declared(construct: construct, authoredName: construct.rawValue),
            operation: .compilation,
            source: construct.rawValue,
            sourcePath: path,
            sourceSpan: .init(location: .unavailable, utf8Length: construct.rawValue.utf8.count),
            expected: capability.boundary,
            actual: "\(actualDescription(for: construct)) inside Algorithm",
            nextSafeAction: capability.nextSafeAction
        )
    }

    private static func actualDescription(for construct: DeclaredLanguageConstruct) -> String {
        switch construct {
        case .genericFairness:
            "generic fairness declaration"
        case .algorithmAssume:
            "Assume declaration"
        default:
            construct.rawValue
        }
    }
}
