/// Reports a generated-machine execution failure.
public enum GeneratedMachineError: Error, Sendable {
    case noInitialState
    case ambiguousInitialState
    case invalidInitialState
    case noMatchingSuccessor
    case ambiguousAction
}

public enum GeneratedMachineStateDiagnostic: Error, Sendable, Equatable {
    case typeMismatch(path: String, expected: String, actual: String)
}
