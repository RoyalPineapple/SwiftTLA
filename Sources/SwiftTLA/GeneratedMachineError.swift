/// Reports a generated-machine execution failure.
public enum GeneratedMachineError: Error, Sendable {
    case noInitialState
    case ambiguousInitialState
    case invalidInitialState
    case noMatchingSuccessor
    case ambiguousAction
    case liveMachineUnavailable(String)
    case identityRoutedActionRequiresID
    case invalidGeneratedActionOrdinal
    case invalidGeneratedVariableOrdinal
}

/// Reports a generated state that cannot decode one compiled value.
public enum GeneratedMachineStateDiagnostic: Error, Sendable, Equatable {
    case missingRequiredValue(path: String, expected: String)
    case typeMismatch(path: String, expected: String, actual: String)
}
