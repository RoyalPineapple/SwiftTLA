import SwiftTLA

@attached(member, names: arbitrary)
@attached(extension, conformances: TLAModelType, names: arbitrary)
public macro TLAModel() = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: arbitrary)
@attached(extension, conformances: TLAModelType, names: arbitrary)
public macro TLAActor() = #externalMacro(module: "SwiftTLAPlugin", type: "TLAActorMacro")

@attached(peer, names: arbitrary)
public macro TypedVar() = #externalMacro(module: "SwiftTLAPlugin", type: "TypedVarMacro")
