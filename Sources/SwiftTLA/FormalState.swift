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

    init(projected valuesByName: [String: TLAValue], layout: CompiledLayout) throws {
        let expectedNames = Set(layout.variables.map(\.declaration.name))
        guard Set(valuesByName.keys) == expectedNames else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: expectedNames.count,
                actual: valuesByName.count
            )
        }
        let values = try layout.variables.map { variable in
            guard let value = valuesByName[variable.declaration.name] else {
                throw CompiledEvaluationError.invalidStateLayout(
                    expected: expectedNames.count,
                    actual: valuesByName.count
                )
            }
            return value
        }
        try self.init(values: values, layout: layout)
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

    func updating(_ assignments: [VariableID: TLAValue]) throws -> FormalState {
        var updated = self
        for assignment in assignments {
            updated = try updated.updating(assignment.key, to: assignment.value)
        }
        return updated
    }

    func transformingValues(_ transform: (TLAValue) -> TLAValue) -> FormalState {
        FormalState(validatedValues: values.map(transform))
    }

    func contains(_ value: TLAValue) -> Bool {
        values.contains { valueContains($0, value) }
    }

    func projected(using layout: CompiledLayout) throws -> [String: TLAValue] {
        guard values.count == layout.variables.count else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: layout.variables.count,
                actual: values.count
            )
        }
        return Dictionary(uniqueKeysWithValues: layout.variables.map { variable in
            (variable.declaration.name, values[variable.id.ordinal])
        })
    }

    var canonicalEncoding: String {
        values.map(symmetricValueEncoding).joined(separator: "|")
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
    case unresolvedOperator
    case conflictingAssignment(VariableID)
}
