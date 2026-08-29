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
        private let values: [_GeneratedMachineValue]
        private let layout: CompiledLayout
        private var index = 0

        fileprivate init(_ values: [_GeneratedMachineValue], layout: CompiledLayout) {
            self.values = values
            self.layout = layout
        }

        public mutating func decode<Value: TLAValueType>(
            as _: Value.Type = Value.self
        ) throws -> Value {
            let actual = values.indices.contains(index)
                ? values[index].diagnosticKind
                : "no input at index \(index) among \(values.count) decoder inputs"
            guard values.indices.contains(index),
                  case .value(let compiled, let path) = values[index] else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .runtime,
                    path: "generatedValueDecoder[\(index)]",
                    expected: "a compiled value decodable as \(String(reflecting: Value.self))",
                    actual: actual,
                    nextSafeAction: "Compile the generated machine from its current source declaration."
                )
            }
            defer { index += 1 }
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
            let actual = values.indices.contains(index)
                ? "\(values[index].diagnosticKind) for \(applicationMembers.count) application members"
                : "no input at index \(index) among \(values.count) decoder inputs"
            guard values.indices.contains(index),
                  case .member(let memberIndex) = values[index],
                  applicationMembers.indices.contains(memberIndex) else {
                throw CompilationDiagnostic(
                    code: .compilationIdentityMismatch,
                    stage: .runtime,
                    path: "generatedValueDecoder[\(index)]",
                    expected: "a symmetric member index within the bound application members",
                    actual: actual,
                    nextSafeAction: "Compile the generated machine from its current source declaration."
                )
            }
            index += 1
            return applicationMembers[memberIndex]
        }

        public mutating func decodeCollection<Member: Hashable & Sendable, Value: TLAValueType>(
            applicationMembers: [Member],
            as _: Value.Type = Value.self
        ) throws -> [Member: Value] {
            guard values.indices.contains(index),
                  case .collection(let compiledValues, let path) = values[index] else {
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
            index += 1
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
            index == values.endIndex
        }

        fileprivate var remainingCount: Int {
            values.endIndex - index
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
            return (compiled, state)
        }
        let matches = if let initial {
            decoded.filter { $0.1 == initial }
        } else {
            decoded
        }
        guard matches.count == 1 else {
            if matches.isEmpty {
                if initial == nil {
                    throw GeneratedMachineError.noInitialState
                }
                throw GeneratedMachineError.invalidInitialState
            }
            throw GeneratedMachineError.ambiguousInitialState
        }
        self.compilation = compilation
        self.stateDecoder = stateDecoder
        self.actionDecoders = actionDecoders
        self.actionValidator = actionValidator
        self.compiledState = matches[0].0
        self.state = matches[0].1
    }

    public func isEnabled(_ action: Action) throws -> Bool {
        try actionValidator(action)
        return try candidates().contains { $0.action == action }
    }

    public func enabledActions() throws -> [Action] {
        var seen = Set<Action>()
        return try candidates().compactMap { candidate in
            seen.insert(candidate.action).inserted ? candidate.action : nil
        }
    }

    public mutating func send(_ action: Action) throws -> (before: State, after: State) {
        try actionValidator(action)
        let matches = try candidates().filter { $0.action == action }
        guard matches.count == 1 else {
            if matches.isEmpty {
                throw GeneratedMachineError.noMatchingSuccessor
            }
            throw GeneratedMachineError.ambiguousAction
        }
        let before = state
        let successor = matches[0]
        var values = try Self.stateValues(successor.compiledState, compilation: compilation)
        let after = try stateDecoder(&values)
        try Self.validateStateDecoder(values)
        compiledState = successor.compiledState
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
            if case .some = planAction.symmetricCollection {
                guard input.arguments.count == 1,
                      let action = compilation.semantics.actions.first(where: { $0.id == request.action }),
                      let collectionVariable = action.symmetricCollection,
                      compilation.layout.variables.indices.contains(collectionVariable.ordinal),
                      let compiledMembers = compilation.layout.variables[collectionVariable.ordinal]
                        .symmetricCollection?.members,
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
            guard case .some = variable.symmetricCollection else {
                return _GeneratedMachineValue.value(compiled, path: variable.formalName)
            }
            guard case .function(let entries) = compiled,
                  let compiledMembers = layout.symmetricCollection?.members else {
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
