public enum AlgorithmDiagnosticCode: String, Sendable, Hashable {
    case reservedName
    case invalidName
    case emptyDomain
    case duplicateDomainMember
    case duplicateLabel
    case invalidTarget
    case duplicateRootWrite
    case missingStop
    case propertyBoundary
    case invalidAlgorithmComponent
    case duplicateProcedure
    case duplicateProcedureVariable
    case invalidProcedureTarget
    case invalidProcedureArity
    case invalidProcedureReturn
    case invalidProcedureControlFlow
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
