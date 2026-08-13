import SwiftTLA

/// Generates a typed model machine from the declaration's `TLASpec`.
///
/// The generated surface includes `State`, `ActionLabel`, `TransitionResult`,
/// execution methods, and bounded verification helpers.
@attached(member, names: arbitrary)
@attached(extension, conformances: Sendable, TLAModelType, TLAMachineExecuting, TLAMachineAdapterCanonicalModel, names: arbitrary)
public macro TLAModel() = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

/// Generates an actor machine or a nested actor adapter for a `@TLAModel`.
///
/// A nested adapter exposes the enclosing model's typed state and transition
/// result through type aliases.
@attached(member, names: arbitrary)
@attached(extension, conformances: TLAModelType, TLAMachineAdapterAccess, names: arbitrary)
public macro TLAActor() = #externalMacro(module: "SwiftTLAPlugin", type: "TLAActorMacro")

/// Generates an observable machine or a nested main-actor observable adapter.
///
/// A nested adapter calls its typed `on<Action>` callback after a successful
/// transition commits.
@attached(member, names: arbitrary)
@attached(extension, conformances: Sendable, TLAMachineAdapterAccess, names: arbitrary)
public macro TLAObservable() = #externalMacro(module: "SwiftTLAPlugin", type: "TLAObservableMacro")

@attached(peer, names: arbitrary)
public macro TypedVar() = #externalMacro(module: "SwiftTLAPlugin", type: "TypedVarMacro")
