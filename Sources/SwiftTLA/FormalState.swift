struct FormalState: Hashable, Sendable {
    private let compilationIdentity: CompilationIdentity
    private let values: [CompiledValue]

    init(formalValues values: [TLAValue], compilation: CompiledSpecification) throws {
        try self.init(values: values.map { .init(formal: $0) }, compilation: compilation)
    }

    init(values: [CompiledValue], compilation: CompiledSpecification) throws {
        guard values.count == compilation.layout.variables.count else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: compilation.layout.variables.count,
                actual: values.count
            )
        }
        self.init(validatedValues: values, compilationIdentity: compilation.identity)
    }

    init(projected valuesByName: [String: TLAValue], compilation: CompiledSpecification) throws {
        let expectedNames = Set(compilation.layout.variables.map(\.declaration.name))
        guard Set(valuesByName.keys) == expectedNames else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: expectedNames.count,
                actual: valuesByName.count
            )
        }
        let values: [CompiledValue] = try compilation.layout.variables.map { variable in
            guard let value = valuesByName[variable.declaration.name] else {
                throw CompiledEvaluationError.invalidStateLayout(
                    expected: expectedNames.count,
                    actual: valuesByName.count
                )
            }
            return CompiledValue(formal: value)
        }
        try self.init(values: values, compilation: compilation)
    }

    func value(for variable: VariableID) throws -> CompiledValue {
        guard values.indices.contains(variable.ordinal) else {
            throw CompiledEvaluationError.invalidVariableID(variable)
        }
        return values[variable.ordinal]
    }

    func updating(_ variable: VariableID, to value: CompiledValue) throws -> FormalState {
        guard values.indices.contains(variable.ordinal) else {
            throw CompiledEvaluationError.invalidVariableID(variable)
        }
        var updated = values
        updated[variable.ordinal] = value
        return FormalState(validatedValues: updated, compilationIdentity: compilationIdentity)
    }

    func updating(_ assignments: [VariableID: CompiledValue]) throws -> FormalState {
        var updated = self
        for assignment in assignments {
            updated = try updated.updating(assignment.key, to: assignment.value)
        }
        return updated
    }

    func transformingFormalValues(_ transform: (TLAValue) -> TLAValue) -> FormalState {
        FormalState(
            validatedValues: values.map { $0.transformingFormalValues(transform) },
            compilationIdentity: compilationIdentity
        )
    }

    func contains(_ value: TLAValue) -> Bool {
        values.contains { $0.contains(value) }
    }

    func projected(using layout: CompiledLayout) throws -> [String: TLAValue] {
        guard values.count == layout.variables.count else {
            throw CompiledEvaluationError.invalidStateLayout(
                expected: layout.variables.count,
                actual: values.count
            )
        }
        return try Dictionary(uniqueKeysWithValues: layout.variables.map { variable in
            (variable.declaration.name, try values[variable.id.ordinal].rendered(using: layout))
        })
    }

    func requireIdentity(_ identity: CompilationIdentity) throws {
        guard compilationIdentity == identity else {
            throw CompiledEvaluationError.invalidCompilationIdentity(
                expected: identity,
                actual: compilationIdentity
            )
        }
    }

    func canonicalEncoding(using layout: CompiledLayout) throws -> String {
        try values.map { symmetricValueEncoding(try $0.rendered(using: layout)) }.joined(separator: "|")
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
    case invalidControlLabelID(ControlLabelID)
    case invalidCompilationIdentity(expected: CompilationIdentity, actual: CompilationIdentity)
    case unboundBinder(BinderID)
    case unresolvedOperator
    case conflictingAssignment(VariableID)
}
