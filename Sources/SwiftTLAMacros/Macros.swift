@freestanding(declaration, names: named(TLAStateMachine))
public macro TLAModel(_ body: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(peer, names: named(TLAStateMachine))
@attached(member, names: named(spec))
public macro TLAModel() = #externalMacro(module: "SwiftTLAPlugin", type: "AttachedTLASpecMacro")

@attached(member, names: named(spec))
public macro TLAActor() = #externalMacro(module: "SwiftTLAPlugin", type: "AttachedTLASpecMacro")
