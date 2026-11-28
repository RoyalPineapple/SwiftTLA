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

package struct NativeAlternativeFailure: Equatable, Sendable {
    package struct Binding: Equatable, Sendable {
        package let binding: Int
        package let target: Int
        package let value: Int
    }

    package enum Location: Equatable, Sendable {
        case sharedPrefix
        case arm(Int)
    }

    package let action: Int
    package let location: Location
    package let site: Int
    package let target: Int
    package let before: [Binding]
    package let reason: NativeMachineEvaluationError
}

private enum AssignmentFailureObservation: Sendable {
    case addition(NativeOrderedIntAssignmentFailure)
    case alternative(NativeAlternativeFailure)
}

/// Run-owned data that does not participate in model-state identity.
public struct CheckingContext<Registers: Sendable>: Sendable {
    public var registers: Registers
    public private(set) var level: Int = 0
    private var assignmentFailures: [AssignmentFailureObservation]?
    fileprivate private(set) var recordsAlternativeFailures = false

    /// Reached addition failures retained during checked execution, if enabled.
    public var orderedIntAssignmentFailures: [NativeOrderedIntAssignmentFailure]? {
        guard !recordsAlternativeFailures else { return nil }
        return assignmentFailures?.compactMap {
            guard case .addition(let failure) = $0 else { return nil }
            return failure
        }
    }

    fileprivate var recordsOrderedIntAssignmentFailures: Bool {
        !recordsAlternativeFailures && assignmentFailures != nil
    }

    public init(registers: Registers) {
        self.registers = registers
    }

    public mutating func startRecordingOrderedIntAssignmentFailures() {
        recordsAlternativeFailures = false
        assignmentFailures = []
    }

    package mutating func startRecordingActionFailureHistory() {
        recordsAlternativeFailures = true
        assignmentFailures = []
    }

    package mutating func finishRecordingActionFailureHistory() -> [NativeAlternativeFailure] {
        guard recordsAlternativeFailures else { return [] }
        defer {
            assignmentFailures = nil
            recordsAlternativeFailures = false
        }
        return assignmentFailures?.compactMap {
            guard case .alternative(let failure) = $0 else { return nil }
            return failure
        } ?? []
    }

    fileprivate mutating func record(_ observation: AssignmentFailureObservation) {
        assignmentFailures?.append(observation)
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
    guard context?.recordsOrderedIntAssignmentFailures == true,
          case .integerOverflow(.addition, _) = reason else { return }
    context?.record(.addition(.init(actionOrdinal: actionOrdinal, assignmentOrdinal: assignmentOrdinal,
                                    preceding: preceding(), reason: reason)))
}


@_documentation(visibility: internal)
public func _recordNativeAlternativeFailure<Registers>(
    _ context: inout CheckingContext<Registers>?, action: Int, branch: Int, site: Int, target: Int,
    before: @autoclosure () -> [(binding: Int, target: Int, value: Int)], reason: NativeMachineEvaluationError
) {
    guard context?.recordsAlternativeFailures == true else { return }
    let bindings = before().map { NativeAlternativeFailure.Binding(binding: $0.binding, target: $0.target, value: $0.value) }
    context?.record(.alternative(.init(action: action, location: .arm(branch), site: site, target: target,
                                       before: bindings, reason: reason)))
}

@_documentation(visibility: internal)
public func _recordNativeSharedPrefixFailure<Registers>(
    _ context: inout CheckingContext<Registers>?, action: Int, site: Int, target: Int,
    before: @autoclosure () -> [(binding: Int, target: Int, value: Int)], reason: NativeMachineEvaluationError
) {
    guard context?.recordsAlternativeFailures == true else { return }
    let bindings = before().map { NativeAlternativeFailure.Binding(binding: $0.binding, target: $0.target, value: $0.value) }
    context?.record(.alternative(.init(action: action, location: .sharedPrefix, site: site, target: target,
                                       before: bindings, reason: reason)))
}
