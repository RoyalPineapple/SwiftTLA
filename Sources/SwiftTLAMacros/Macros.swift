@attached(peer, names: named(TLAStateMachine))
@attached(member, names: named(spec))
public macro TLAModel() = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: named(spec))
public macro TLAActor() = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")
