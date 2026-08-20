import Foundation

/// A typed action label that denotes one formal action invocation.
///
/// Generated action labels already expose `toInvocation()`, so a generated
/// surface satisfies this contract with a bare conformance declaration.
/// Typed and generic execution both reduce their request to one formal
/// invocation and route it through the same live-runtime pipeline.
public protocol TLALiveActionLabel: Sendable {
    /// The formal invocation this label denotes.
    func toInvocation() -> TLAActionInvocation
}

/// The facts a generated model supplies to bind its compiled specification
/// to the one authoritative live runtime.
///
/// The schema and the formal behavior come from the existing compiled-model
/// surface: `machineSchema` describes the model's declared shape, `runtime`
/// is the formal evaluator, and the recorded metadata identifies the exact
/// schema. The runtime never duplicates transition semantics; the generated
/// model supplies only decoding and routing facts around the evaluator.
public protocol TLAGeneratedLiveModel: TLAMachineSchemaProviding, Sendable {
    /// The formal runtime of the model's compiled specification.
    static var runtime: SpecRuntime { get }
    /// The metadata emitted next to the generated machine surface.
    static var generatedMachineMetadata: GeneratedMachineMetadata { get }
    /// Validates that a formal projection decodes as the model's typed State.
    static func decodeState(_ projection: TLAStateProjection) throws
    /// Formal action names that select an identified collection member and
    /// therefore cannot be routed through a generic invocation.
    static var identityRoutedActionNames: Set<String> { get }
}

public extension TLAGeneratedLiveModel {
    static var identityRoutedActionNames: Set<String> { [] }
}

/// A structured failure at the generated-model live-runtime boundary.
///
/// Binding validates the generated schema against the compiled specification
/// before any runtime is accepted; every rejected incompatibility is reported
/// here with the path, the expected shape, the observed shape, and the safe
/// recovery step.
public struct GeneratedLiveMachineDiagnostic: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, Equatable {
        case schemaFormatMismatch
        case schemaIdentifierMismatch
        case stateFieldMismatch
        case duplicateStateField
        case actionMismatch
        case duplicateAction
        case actionParameterMismatch
        case noInitialState
        case initialProjectionFailed
        case initialDecodeFailed
        case handleSchemaMismatch
    }

    public let code: Code
    public let path: String
    public let expected: String
    public let actual: String
    public let nextSafeAction: String

    public init(
        code: Code,
        path: String,
        expected: String,
        actual: String,
        nextSafeAction: String
    ) {
        self.code = code
        self.path = path
        self.expected = expected
        self.actual = actual
        self.nextSafeAction = nextSafeAction
    }

    public var description: String {
        "Generated live machine binding failed [\(code.rawValue)] at \(path). "
            + "Expected: \(expected). Actual: \(actual). Next safe action: \(nextSafeAction)"
    }
}

/// The generated-model handle to the one authoritative live runtime.
///
/// Construction validates that the supplied handle exposes exactly the
/// model's generated schema, so a typed request can never reach a runtime
/// compiled from a different model. Typed labels and generic invocations are
/// both reduced to their formal invocation and executed through the same
/// runtime pipeline with identical formal effects.
public struct GeneratedLiveMachine<Model: TLAGeneratedLiveModel>: Sendable {
    /// The underlying common runtime handle.
    public let handle: TLALiveMachine

    /// Binds an existing runtime handle, validating that its schema is
    /// exactly the model's generated schema.
    public init(handle: TLALiveMachine) throws {
        guard handle.schema == Model.machineSchema else {
            throw GeneratedLiveMachineDiagnostic(
                code: .handleSchemaMismatch,
                path: "handle",
                expected: Model.machineSchema.identifier,
                actual: handle.schema.identifier,
                nextSafeAction: "Bind a handle created for \(Model.machineSchema.model.name), "
                    + "or create the runtime from the same generated model."
            )
        }
        self.handle = handle
    }

    /// The stable runtime identity shared by every handle of this machine.
    public var identity: TLALiveMachineIdentity { handle.identity }

    /// The generated schema this machine exposes.
    public var schema: MachineSchema { handle.schema }

    /// The current committed snapshot, or the reason none is available.
    public func current() async -> TLALiveMachineCurrentResult {
        await handle.current()
    }

    /// Executes a generic invocation through the common runtime pipeline.
    public func execute(
        _ invocation: TLAActionInvocation,
        requestID: UUID = UUID()
    ) async -> TLALiveActionOutcome {
        await handle.execute(invocation, requestID: requestID)
    }

    /// Executes a typed action label through the same runtime pipeline.
    ///
    /// The label is converted to its formal invocation and routed through
    /// the identical execution path as a generic request.
    public func execute(
        _ label: some TLALiveActionLabel,
        requestID: UUID = UUID()
    ) async -> TLALiveActionOutcome {
        await handle.execute(label.toInvocation(), requestID: requestID)
    }

    /// Builds the transition driver that binds the model's formal runtime to
    /// the live transition pipeline.
    ///
    /// Successor computation and availability enumeration come from the
    /// existing formal evaluator; the generated model contributes only state
    /// decoding, finite-domain validation, and identity-routed action facts.
    public static func transitionDriver() -> TLALiveMachineTransitionDriver {
        let runtime = Model.runtime
        let formalActions = Dictionary(
            uniqueKeysWithValues: runtime.spec.actions.map { ($0.name, $0) }
        )
        let identityRouted = Model.identityRoutedActionNames
        return TLALiveMachineTransitionDriver(
            successors: { projection, invocation in
                try runtime.successors(invocation, from: projection)
            },
            availableInvocations: { projection in
                try runtime.availableInvocations(in: projection).filter {
                    !identityRouted.contains($0.name)
                }
            },
            validateInvocation: { invocation in
                guard let action = formalActions[invocation.name] else {
                    return .unknownAction
                }
                guard action.bindings.count == invocation.arguments.count else {
                    return .invalidArity
                }
                for (binding, argument) in zip(action.bindings, invocation.arguments)
                where !binding.values.contains(argument) {
                    return .actionArgumentOutOfDomain
                }
                if identityRouted.contains(invocation.name) {
                    return .identityRoutedActionRequiresID
                }
                return nil
            },
            decodeState: { projection in
                try Model.decodeState(projection)
            }
        )
    }

}

extension TLALiveMachineOwner {
    /// Creates a new live runtime bound to a generated model's compiled
    /// specification.
    ///
    /// The generated schema is validated against the compiled specification
    /// before any runtime is constructed: the schema format, schema
    /// identifier, state fields, action names, and action parameters must
    /// match exactly. The runtime starts from the model's first initial
    /// state and executes transitions through the model's formal evaluator.
    public static func create<Model: TLAGeneratedLiveModel>(
        for model: Model.Type
    ) throws -> TLALiveMachineOwner {
        let schema = Model.machineSchema
        let metadata = Model.generatedMachineMetadata
        let runtime = Model.runtime
        let spec = runtime.spec

        try validateSchemaCompatibility(schema: schema, metadata: metadata, spec: spec)

        let initialStates = try runtime.initialStateProjections()
        guard let initial = initialStates.first else {
            throw GeneratedLiveMachineDiagnostic(
                code: .noInitialState,
                path: "initialStates",
                expected: "at least one formal initial state",
                actual: "no initial states",
                nextSafeAction: "Declare an initial state for the model before creating a live runtime."
            )
        }
        do {
            try Model.decodeState(initial)
        } catch {
            throw GeneratedLiveMachineDiagnostic(
                code: .initialDecodeFailed,
                path: "initialStates",
                expected: "the generated State to decode the model's initial projection",
                actual: String(describing: error),
                nextSafeAction: "Correct the generated State decoding, then create the runtime again."
            )
        }

        return TLALiveMachineOwner.create(
            schema: schema,
            initial: initial,
            driver: GeneratedLiveMachine<Model>.transitionDriver()
        )
    }

    private static func validateSchemaCompatibility(
        schema: MachineSchema,
        metadata: GeneratedMachineMetadata,
        spec: TLASpec
    ) throws {
        guard schema.formatVersion == MachineSchema.formatVersion else {
            throw GeneratedLiveMachineDiagnostic(
                code: .schemaFormatMismatch,
                path: "machineSchema.formatVersion",
                expected: String(MachineSchema.formatVersion),
                actual: String(schema.formatVersion),
                nextSafeAction: "Regenerate the machine surface from the current SwiftTLA schema format."
            )
        }
        guard schema.identifier == metadata.schemaIdentifier else {
            throw GeneratedLiveMachineDiagnostic(
                code: .schemaIdentifierMismatch,
                path: "machineSchema.identifier",
                expected: metadata.schemaIdentifier,
                actual: schema.identifier,
                nextSafeAction: "Regenerate the machine surface from the same compiled specification."
            )
        }

        let schemaStateIDs = schema.state.map(\.id)
        guard Set(schemaStateIDs).count == schemaStateIDs.count else {
            throw GeneratedLiveMachineDiagnostic(
                code: .duplicateStateField,
                path: "machineSchema.state",
                expected: "one state field per formal variable",
                actual: "a repeated state field id",
                nextSafeAction: "Regenerate the machine schema so every formal variable appears once."
            )
        }
        let formalStateNames = spec.variables.map(\.name)
        guard Set(schemaStateIDs) == Set(formalStateNames) else {
            throw GeneratedLiveMachineDiagnostic(
                code: .stateFieldMismatch,
                path: "machineSchema.state",
                expected: formalStateNames.sorted().joined(separator: ", "),
                actual: schemaStateIDs.sorted().joined(separator: ", "),
                nextSafeAction: "Regenerate the machine schema from the same compiled specification."
            )
        }

        let schemaActionIDs = schema.actions.map(\.id)
        guard Set(schemaActionIDs).count == schemaActionIDs.count else {
            throw GeneratedLiveMachineDiagnostic(
                code: .duplicateAction,
                path: "machineSchema.actions",
                expected: "one schema action per formal action",
                actual: "a repeated action id",
                nextSafeAction: "Regenerate the machine schema so every formal action appears once."
            )
        }
        let formalActionsByName = Dictionary(
            uniqueKeysWithValues: spec.actions.map { ($0.name, $0) }
        )
        guard Set(schemaActionIDs) == Set(formalActionsByName.keys) else {
            throw GeneratedLiveMachineDiagnostic(
                code: .actionMismatch,
                path: "machineSchema.actions",
                expected: spec.actions.map(\.name).sorted().joined(separator: ", "),
                actual: schemaActionIDs.sorted().joined(separator: ", "),
                nextSafeAction: "Regenerate the machine schema from the same compiled specification."
            )
        }
        for action in schema.actions {
            guard let formalAction = formalActionsByName[action.id] else {
                throw GeneratedLiveMachineDiagnostic(
                    code: .actionMismatch,
                    path: "machineSchema.actions",
                    expected: "a declared formal action for \(action.id)",
                    actual: "no matching formal action",
                    nextSafeAction: "Regenerate the machine schema from the same compiled specification."
                )
            }
            let schemaParameterIDs = action.parameters.map(\.id)
            let formalParameterNames = formalAction.bindings.map(\.name)
            guard schemaParameterIDs == formalParameterNames else {
                throw GeneratedLiveMachineDiagnostic(
                    code: .actionParameterMismatch,
                    path: "machineSchema.actions.\(action.id).parameters",
                    expected: formalParameterNames.joined(separator: ", "),
                    actual: schemaParameterIDs.joined(separator: ", "),
                    nextSafeAction: "Regenerate the machine schema so action parameters match the declared formal bindings."
                )
            }
        }
    }
}
