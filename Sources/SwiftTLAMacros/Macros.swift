@freestanding(declaration, names: named(TLAStateMachine))
public macro TLA(_ body: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(peer, names: named(TLAStateMachine))
@attached(member, names: named(spec))
public macro TLASpec() = #externalMacro(module: "SwiftTLAPlugin", type: "AttachedTLASpecMacro")
