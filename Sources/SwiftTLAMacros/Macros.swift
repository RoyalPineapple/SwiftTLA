import SwiftTLA

@attached(member, names: arbitrary)
@attached(extension, conformances: Sendable, TLAModelType, TLAMachineExecuting, TLAMachineAdapterCanonicalModel, names: arbitrary)
public macro TLAModel() = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: TLAModelType, TLAMachineAdapterAccess, names: arbitrary)
public macro TLAActor() = #externalMacro(module: "SwiftTLAPlugin", type: "TLAActorMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: Sendable, TLAMachineAdapterAccess, names: arbitrary)
public macro TLAObservable() = #externalMacro(module: "SwiftTLAPlugin", type: "TLAObservableMacro")

@attached(peer, names: arbitrary)
public macro TypedVar() = #externalMacro(module: "SwiftTLAPlugin", type: "TypedVarMacro")
