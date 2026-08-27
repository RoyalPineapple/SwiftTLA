import Foundation

/// Storage for one generated Swift machine and its compiled specification.
public struct _GeneratedMachineStorage: Sendable {
    /// An opaque state from this storage's compiled specification.
    public struct State: Hashable, Sendable {
        fileprivate let compiled: CompiledState

        fileprivate init(_ compiled: CompiledState) {
            self.compiled = compiled
        }
    }

    /// Opaque action arguments passed between generated members and storage.
    public struct ActionArguments: Sendable {
        fileprivate let values: [TLAValue]

        public var count: Int { values.count }
        public var isEmpty: Bool { values.isEmpty }

        public func value<Value: TLAValueType>(
            at index: Int,
            as _: Value.Type = Value.self
        ) throws -> Value {
            guard values.indices.contains(index) else {
                throw GeneratedMachineError.invalidGeneratedActionOrdinal
            }
            return try _GeneratedMachineStorage.decode(values[index], at: "action argument \(index)")
        }

        public func matches(
            _ value: TLAValue,
            at index: Int
        ) -> Bool {
            values.indices.contains(index) && values[index] == value
        }
    }

    private let compilation: CompiledSpecification

    /// Creates generated-machine storage from one successful compilation.
    public init(compilation: CompiledSpecification) {
        self.compilation = compilation
    }

    /// Returns every initial state from the compiled specification.
    public func initialStates() throws -> [State] {
        try CompiledRuntime(compilation: compilation).initialStates().map(State.init)
    }

    /// Returns the declared initial state matching the generated state's values.
    public func initialState(matching predicate: (State) throws -> Bool) throws -> State {
        let matches = try CompiledRuntime(compilation: compilation).initialStates()
            .map(State.init)
            .filter(predicate)
        guard matches.count == 1 else {
            if matches.isEmpty {
                throw GeneratedMachineError.invalidInitialState
            }
            throw GeneratedMachineError.ambiguousInitialState
        }
        return matches[0]
    }

    /// Returns the formal value at one generated variable ordinal.
    public func value<Value: TLAValueType>(
        at variableOrdinal: Int,
        as _: Value.Type = Value.self,
        in state: State
    ) throws -> Value {
        guard compilation.layout.variables.indices.contains(variableOrdinal) else {
            throw GeneratedMachineError.invalidGeneratedVariableOrdinal
        }
        let variable = compilation.layout.variables[variableOrdinal]
        let formalValue = try state.compiled.value(for: variable.id).rendered(using: compilation.layout)
        return try Self.decode(formalValue, at: variable.declaration.name)
    }

    public func collectionValue<Value: TLAValueType, Member: TLAValueConvertible>(
        at variableOrdinal: Int,
        for member: Member,
        as _: Value.Type = Value.self,
        in state: State
    ) throws -> Value? {
        guard case .function(let values) = try value(
            at: variableOrdinal,
            as: TLAValue.self,
            in: state
        ), let value = values[member.tlaValue] else {
            return nil
        }
        return try Self.decode(value, at: "collection member")
    }

    /// Returns every successor for one generated action call.
    public func successors(
        actionOrdinal: Int,
        arguments: [any TLAValueConvertible],
        from state: State
    ) throws -> [State] {
        let request = try request(actionOrdinal: actionOrdinal, arguments: arguments)
        return try CompiledRuntime(compilation: compilation)
            .successors(for: request.action, from: state.compiled)
            .filter { compilation.matches($0.arguments, request: request) }
            .map { State($0.state) }
    }

    /// Resolves the generated actions enabled in one stored state.
    public func availableActions<Action: Hashable>(
        in state: State,
        resolve: (Int, ActionArguments) throws -> Action
    ) throws -> [Action] {
        var seen = Set<Action>()
        var actions: [Action] = []
        for successor in try CompiledRuntime(compilation: compilation).successors(from: state.compiled) {
            let request = CompiledActionRequest(
                action: successor.action,
                arguments: successor.arguments
            )
            let input = try compilation.generatedActionInput(for: request)
            let action = try resolve(input.ordinal, .init(values: input.formalArguments))
            if seen.insert(action).inserted {
                actions.append(action)
            }
        }
        return actions
    }

    private func request(
        actionOrdinal: Int,
        arguments: [any TLAValueConvertible]
    ) throws -> CompiledActionRequest {
        guard compilation.layout.actions.indices.contains(actionOrdinal) else {
            throw GeneratedMachineError.invalidGeneratedActionOrdinal
        }
        return try compilation.actionRequest(
            ordinal: actionOrdinal,
            formalArguments: arguments.map(\.tlaValue)
        )
    }

    private static func decode<Value: TLAValueType>(
        _ formalValue: TLAValue,
        at path: String
    ) throws -> Value {
        guard let value = Value(formalValue: formalValue) else {
            throw GeneratedMachineStateDiagnostic.typeMismatch(
                path: path,
                expected: String(reflecting: Value.self),
                actual: String(describing: formalValue)
            )
        }
        return value
    }
}
