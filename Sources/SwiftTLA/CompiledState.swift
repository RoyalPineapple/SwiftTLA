struct CompiledState: Hashable, Sendable, Comparable {
    private let compilationIdentity: CompilationIdentity
    private let values: [CompiledValue]

    init(values: [CompiledValue], compilation: CompiledSpecification) throws {
        guard values.count == compilation.layout.variables.count else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: compilation.layout.variables.count,
                actual: values.count
            )
        }
        self.init(validatedValues: values, compilationIdentity: compilation.identity)
    }

    func value(for variable: VariableID) throws -> CompiledValue {
        guard values.indices.contains(variable.ordinal) else {
            throw CompiledEvaluationError.invalidVariableID(variable)
        }
        return values[variable.ordinal]
    }

    func updating(_ variable: VariableID, to value: CompiledValue) throws -> CompiledState {
        guard values.indices.contains(variable.ordinal) else {
            throw CompiledEvaluationError.invalidVariableID(variable)
        }
        var updated = values
        updated[variable.ordinal] = value
        return CompiledState(validatedValues: updated, compilationIdentity: compilationIdentity)
    }

    func updating(_ assignments: [VariableID: CompiledValue]) throws -> CompiledState {
        var updated = self
        for assignment in assignments {
            updated = try updated.updating(assignment.key, to: assignment.value)
        }
        return updated
    }

    func applying(_ mapping: [CompiledValue: CompiledValue]) -> CompiledState {
        CompiledState(
            validatedValues: values.map { $0.applying(mapping) },
            compilationIdentity: compilationIdentity
        )
    }

    func projection(using layout: CompiledLayout) throws -> TLAStateProjection {
        guard values.count == layout.variables.count else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: layout.variables.count,
                actual: values.count
            )
        }
        let entries = try layout.variables.map { variable -> TLAStateProjection.Entry in
            guard let token = TLAStateProjection.Token(validating: variable.declaration.name) else {
                throw CompiledEvaluationError.invalidStateLayout(
                    expected: layout.variables.count,
                    actual: values.count
                )
            }
            return .init(
                token: token,
                value: try values[variable.id.ordinal].rendered(using: layout)
            )
        }
        return try TLAStateProjection(validating: entries)
    }

    func requireIdentity(_ identity: CompilationIdentity) throws {
        guard compilationIdentity == identity else {
            throw CompiledEvaluationError.invalidCompilationIdentity(
                expected: identity,
                actual: compilationIdentity
            )
        }
    }

    static func < (lhs: CompiledState, rhs: CompiledState) -> Bool {
        guard lhs.compilationIdentity == rhs.compilationIdentity else {
            return lhs.compilationIdentity.value < rhs.compilationIdentity.value
        }
        return lhs.values.lexicographicallyPrecedes(rhs.values)
    }

    private init(validatedValues: [CompiledValue], compilationIdentity: CompilationIdentity) {
        self.compilationIdentity = compilationIdentity
        values = validatedValues
    }
}

struct CompiledBindings: Sendable {
    private var values: [BinderID: CompiledValue]

    init() {
        values = [:]
    }

    func value(for binder: BinderID) throws -> CompiledValue {
        guard let value = values[binder] else {
            throw CompiledEvaluationError.unboundBinder(binder)
        }
        return value
    }

    func binding(_ value: CompiledValue, to binder: BinderID) -> CompiledBindings {
        var bound = self
        bound.values[binder] = value
        return bound
    }
}

enum CompiledEvaluationError: Error, Sendable {
    case invalidStateLayout(expected: Int, actual: Int)
    case invalidVariableID(VariableID)
    case uninitializedVariable(VariableID)
    case invalidControlLocationID(ControlLocationID)
    case invalidFieldID(FieldID)
    case invalidRecordKey(CompiledValue)
    case invalidCompilationIdentity(expected: CompilationIdentity, actual: CompilationIdentity)
    case unboundBinder(BinderID)
    case unresolvedOperator
    case conflictingAssignment(VariableID)
}
