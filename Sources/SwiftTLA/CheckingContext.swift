/// A reached checked addition that stopped an ordered assignment.
public struct NativeOrderedIntAssignmentFailure: Equatable, Sendable {
    /// Zero-based ordinal of the generated action.
    public let actionOrdinal: Int
    /// One-based ordinal of the assignment within the action.
    public let assignmentOrdinal: Int
    /// Values of earlier assignments in evaluation order, including repeated targets.
    public let preceding: [Int]
    public let reason: NativeMachineEvaluationError
}

/// Run-owned data that does not participate in model-state identity.
public struct CheckingContext<Registers: Sendable>: Sendable {
    public var registers: Registers
    public private(set) var level: Int = 0
    /// Reached assignment failures retained during checked execution, if enabled.
    public private(set) var orderedIntAssignmentFailures: [NativeOrderedIntAssignmentFailure]?

    public init(registers: Registers) {
        self.registers = registers
    }

    public mutating func startRecordingOrderedIntAssignmentFailures() {
        orderedIntAssignmentFailures = []
    }

    fileprivate mutating func record(_ failure: NativeOrderedIntAssignmentFailure) {
        orderedIntAssignmentFailures?.append(failure)
    }

    package mutating func advanceLevel() throws {
        let (next, overflow) = level.addingReportingOverflow(1)
        guard !overflow else { throw ExplorationError.levelOverflow }
        level = next
    }
}

@_documentation(visibility: internal)
public func _recordNativeOrderedIntAssignmentFailure<Registers>(
    _ context: inout CheckingContext<Registers>?, actionOrdinal: Int, assignmentOrdinal: Int,
    preceding: @autoclosure () -> [Int], reason: NativeMachineEvaluationError
) {
    guard context?.orderedIntAssignmentFailures != nil,
          case .integerOverflow(.addition, _) = reason else { return }
    context?.record(.init(actionOrdinal: actionOrdinal, assignmentOrdinal: assignmentOrdinal,
                          preceding: preceding(), reason: reason))
}
