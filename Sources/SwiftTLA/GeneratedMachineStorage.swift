fileprivate enum _GeneratedMachineValue: Sendable {
    case value(CompiledValue, path: String)
    case member(Int)
    case collection([CompiledValue], path: String)

    var diagnosticKind: String {
        switch self {
        case .value: "compiled value"
        case .member(let index): "symmetric member index \(index)"
        case .collection: "compiled collection"
        }
    }
}

@_documentation(visibility: internal)
public struct _GeneratedMachineStorage<State: Equatable & Sendable, Action: Hashable & Sendable>: Sendable {
    public struct Decoder: Sendable {
        private var values: ArraySlice<_GeneratedMachineValue>
        private let layout: CompiledLayout

        fileprivate init(_ values: [_GeneratedMachineValue], layout: CompiledLayout) {
            self.values = values[...]
            self.layout = layout
        }

        public mutating func decode<Value: TLAValueType>(
            as _: Value.Type = Value.self
        ) throws -> Value {
            let actual = values.first?.diagnosticKind
                ?? "no input at index \(values.startIndex) among \(values.endIndex) decoder inputs"
            guard case .value(let compiled, let path)? = values.first else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .runtime,
                    path: "generatedValueDecoder[\(values.startIndex)]",
                    expected: "a compiled value decodable as \(String(reflecting: Value.self))",
                    actual: actual,
                    nextSafeAction: "Compile the generated machine from its current source declaration."
                )
            }
            defer { _ = values.popFirst() }
            let formal = try compiled.rendered(using: layout)
            guard let value = Value(formalValue: formal) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: path,
                    expected: String(reflecting: Value.self),
                    actual: String(describing: formal)
                )
            }
            return value
        }

        public mutating func decodeMember<Member: Equatable & Sendable>(
            applicationMembers: [Member]
        ) throws -> Member {
            let actual = values.first.map {
                "\($0.diagnosticKind) for \(applicationMembers.count) application members"
            } ?? "no input at index \(values.startIndex) among \(values.endIndex) decoder inputs"
            guard case .member(let memberIndex)? = values.first,
                  applicationMembers.indices.contains(memberIndex) else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .runtime,
                    path: "generatedValueDecoder[\(values.startIndex)]",
                    expected: "a symmetric member index within the bound application members",
                    actual: actual,
                    nextSafeAction: "Compile the generated machine from its current source declaration."
                )
            }
            _ = values.popFirst()
            return applicationMembers[memberIndex]
        }

        public mutating func decodeCollection<Member: Hashable & Sendable, Value: TLAValueType>(
            applicationMembers: [Member]
        ) throws -> [Member: Value] {
            guard case .collection(let compiledValues, let path)? = values.first else {
                throw GeneratedMachineStateDiagnostic.missingRequiredValue(
                    path: "generated collection",
                    expected: "one compiled collection value"
                )
            }
            let uniqueApplicationMemberCount = Set(applicationMembers).count
            guard compiledValues.count == applicationMembers.count,
                  uniqueApplicationMemberCount == applicationMembers.count else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: path,
                    expected: "\(compiledValues.count) unique application IDs",
                    actual: "\(uniqueApplicationMemberCount) unique IDs from \(applicationMembers.count) supplied IDs"
                )
            }
            _ = values.popFirst()
            return try Dictionary(uniqueKeysWithValues: zip(applicationMembers, compiledValues).map {
                applicationMember, compiledValue in
                let formalValue = try compiledValue.rendered(using: layout)
                guard let value = Value(formalValue: formalValue) else {
                    throw GeneratedMachineStateDiagnostic.missingRequiredValue(
                        path: path,
                        expected: "a compiled value for every symmetric member"
                    )
                }
                return (applicationMember, value)
            })
        }

        fileprivate var isAtEnd: Bool {
            values.isEmpty
        }

        fileprivate var remainingCount: Int {
            values.count
        }
    }

    private let compilation: CompiledSpecification
    private let stateDecoder: @Sendable (inout Decoder) throws -> State
    private let actionDecoders: [@Sendable (inout Decoder) throws -> Action]
    private let actionValidator: @Sendable (Action) throws -> Void
    private var compiledState: CompiledState
    public private(set) var state: State

    public init(
        compilation: CompiledSpecification,
        initial: State?,
        stateDecoder: @escaping @Sendable (inout Decoder) throws -> State,
        actionDecoders: [@Sendable (inout Decoder) throws -> Action],
        actionValidator: @escaping @Sendable (Action) throws -> Void
    ) throws {
        let initialStates = try CompiledRuntime(compilation: compilation).initialStates()
        let decoded = try initialStates.map { compiled in
            var values = try Self.stateValues(compiled, compilation: compilation)
            let state = try stateDecoder(&values)
            try Self.validateStateDecoder(values)
            return (compiled: compiled, state: state)
        }
        var matches = decoded.filter { initial == nil || initial == $0.state }[...]
        guard let (compiled, state) = matches.popFirst() else {
            if initial == nil {
                throw GeneratedMachineError.noInitialState
            }
            throw GeneratedMachineError.invalidInitialState
        }
        guard matches.isEmpty else {
            throw GeneratedMachineError.ambiguousInitialState
        }
        self.compilation = compilation
        self.stateDecoder = stateDecoder
        self.actionDecoders = actionDecoders
        self.actionValidator = actionValidator
        self.compiledState = compiled
        self.state = state
    }

    public func isEnabled(_ action: Action) throws -> Bool {
        try actionValidator(action)
        return try candidates().contains { $0.action == action }
    }

    public func enabledActions() throws -> [Action] {
        try candidates().map(\.action).reduce(into: (seen: Set<Action>(), actions: [Action]())) { result, action in
            if result.seen.insert(action).inserted {
                result.actions.append(action)
            }
        }.actions
    }

    public mutating func send(_ action: Action) throws -> (before: State, after: State) {
        try actionValidator(action)
        let matches = Set(try candidates().filter { $0.action == action }.map(\.compiledState))
        guard matches.count == 1, let successor = matches.first else {
            if matches.isEmpty {
                throw GeneratedMachineError.noMatchingSuccessor
            }
            throw GeneratedMachineError.ambiguousAction
        }
        let before = state
        var values = try Self.stateValues(successor, compilation: compilation)
        let after = try stateDecoder(&values)
        try Self.validateStateDecoder(values)
        compiledState = successor
        state = after
        return (before, after)
    }

    private func candidates() throws -> [(action: Action, compiledState: CompiledState)] {
        try CompiledRuntime(compilation: compilation).successors(from: compiledState).compactMap { successor in
            let request = CompiledActionRequest(
                action: successor.action,
                arguments: successor.arguments
            )
            guard let input = try compilation.generatedActionInput(for: request) else {
                return nil
            }
            let plan = compilation.machineSurfacePlan
            guard actionDecoders.indices.contains(input.surfaceOrdinal),
                  plan.actions.indices.contains(input.surfaceOrdinal) else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .runtime,
                    path: "machineSurfacePlan.actions[\(input.surfaceOrdinal)]",
                    expected: "one generated action decoder and surface action at generated ordinal \(input.surfaceOrdinal)",
                    actual: "\(actionDecoders.count) decoders and \(plan.actions.count) surface actions",
                    nextSafeAction: "Compile the generated machine from its current source declaration."
                )
            }
            let planAction = plan.actions[input.surfaceOrdinal]
            let generatedValues: [_GeneratedMachineValue]
            if case .some = planAction.collection {
                guard input.arguments.count == 1,
                      let action = compilation.semantics.actions.first(where: { $0.id == request.action }),
                      let collectionVariable = action.collection,
                      compilation.layout.variables.indices.contains(collectionVariable.ordinal),
                      let compiledMembers = compilation.layout.variables[collectionVariable.ordinal]
                        .collection?.members,
                      let memberIndex = compiledMembers.firstIndex(of: input.arguments[0]) else {
                    throw CompilationDiagnostic(
                        code: .compilationIdentityMismatch,
                        stage: .runtime,
                        path: "machineSurfacePlan.actions[\(input.surfaceOrdinal)].\(planAction.swiftIdentifier)",
                        expected: "one compiled argument from the declared symmetric members",
                        actual: "\(input.arguments.count) compiled arguments",
                        nextSafeAction: "Compile the generated machine from its current source declaration."
                    )
                }
                generatedValues = [.member(memberIndex)]
            } else {
                guard input.arguments.count == planAction.bindings.count else {
                    throw CompilationDiagnostic(
                        code: .compilationIdentityMismatch,
                        stage: .runtime,
                        path: "machineSurfacePlan.actions[\(input.surfaceOrdinal)].\(planAction.swiftIdentifier)",
                        expected: "\(planAction.bindings.count) compiled action arguments",
                        actual: "\(input.arguments.count) compiled action arguments",
                        nextSafeAction: "Compile the generated machine from its current source declaration."
                    )
                }
                generatedValues = zip(planAction.bindings, input.arguments).compactMap {
                    binding, compiled in
                    binding.isPublic ? .value(compiled, path: binding.formalName) : nil
                }
            }
            var values = Decoder(generatedValues, layout: compilation.layout)
            let action = try actionDecoders[input.surfaceOrdinal](&values)
            guard values.isAtEnd else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .runtime,
                    path: "machineSurfacePlan.actions[\(input.surfaceOrdinal)].decoder",
                    expected: "every generated action value consumed once",
                    actual: "\(values.remainingCount) unconsumed generated action values",
                    nextSafeAction: "Compile the generated machine from its current source declaration."
                )
            }
            return (action, successor.state)
        }
    }

    private static func stateValues(
        _ state: CompiledState,
        compilation: CompiledSpecification
    ) throws -> Decoder {
        let values = try compilation.machineSurfacePlan.variables.map { variable in
            guard compilation.layout.variables.indices.contains(variable.storageOrdinal) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: variable.formalName,
                    expected: "a compiled layout variable at storage ordinal \(variable.storageOrdinal)",
                    actual: "\(compilation.layout.variables.count) compiled layout variables"
                )
            }
            let layout = compilation.layout.variables[variable.storageOrdinal]
            let compiled = try state.value(for: layout.id)
            guard case .some = variable.collection else {
                return _GeneratedMachineValue.value(compiled, path: variable.formalName)
            }
            guard case .function(let entries) = compiled,
                  let compiledMembers = layout.collection?.members else {
                let actual = switch compiled {
                case .integer: "integer"
                case .boolean: "boolean"
                case .string: "string"
                case .controlLocation: "control location"
                case .set: "set"
                case .tuple: "tuple"
                case .record: "record"
                case .function: "function without symmetric collection layout"
                case .constant: "constant"
                }
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: variable.formalName,
                    expected: "a compiled function over the declared symmetric members",
                    actual: actual
                )
            }
            guard entries.count == compiledMembers.count else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: variable.formalName,
                    expected: "exactly the declared symmetric collection domain",
                    actual: "\(entries.count) entries for \(compiledMembers.count) declared members"
                )
            }
            let memberValues = try compiledMembers.map { member in
                guard let value = entries[member] else {
                    throw GeneratedMachineStateDiagnostic.missingRequiredValue(
                        path: variable.formalName,
                        expected: "a compiled value for every symmetric member"
                    )
                }
                return value
            }
            return _GeneratedMachineValue.collection(memberValues, path: variable.formalName)
        }
        return Decoder(values, layout: compilation.layout)
    }

    private static func validateStateDecoder(_ decoder: Decoder) throws {
        guard decoder.isAtEnd else {
            throw GeneratedMachineStateDiagnostic.typeMismatch(
                path: "generated state decoder",
                expected: "every compiled surface variable consumed once",
                actual: "\(decoder.remainingCount) unconsumed compiled values"
            )
        }
    }
}
