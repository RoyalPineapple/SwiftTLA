struct FormalState: Hashable, Sendable {
    private let values: [TLAValue]

    init(values: [TLAValue], layout: CompiledLayout) throws {
        guard values.count == layout.variables.count else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: layout.variables.count,
                actual: values.count
            )
        }
        self.init(validatedValues: values)
    }

    func value(for variable: VariableID) throws -> TLAValue {
        guard values.indices.contains(variable.ordinal) else {
            throw CompiledEvaluationError.invalidVariableID(variable)
        }
        return values[variable.ordinal]
    }

    func updating(_ variable: VariableID, to value: TLAValue) throws -> FormalState {
        guard values.indices.contains(variable.ordinal) else {
            throw CompiledEvaluationError.invalidVariableID(variable)
        }
        var updated = values
        updated[variable.ordinal] = value
        return FormalState(validatedValues: updated)
    }

    private init(validatedValues: [TLAValue]) {
        values = validatedValues
    }
}

struct CompiledBindings: Sendable {
    private var values: [BinderID: TLAValue]

    init() {
        values = [:]
    }

    func value(for binder: BinderID) throws -> TLAValue {
        guard let value = values[binder] else {
            throw CompiledEvaluationError.unboundBinder(binder)
        }
        return value
    }

    func binding(_ value: TLAValue, to binder: BinderID) -> CompiledBindings {
        var bound = self
        bound.values[binder] = value
        return bound
    }
}

enum CompiledEvaluationError: Error, Sendable {
    case invalidStateLayout(expected: Int, actual: Int)
    case invalidVariableID(VariableID)
    case unboundBinder(BinderID)
    case unsupportedExpression
    case unresolvedOperator
    case conflictingAssignment(VariableID)
}
