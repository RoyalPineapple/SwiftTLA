@freestanding(declaration, names: named(TLAStateMachine))
public macro TLASpec(_ body: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(peer, names: named(StateMachine))
public macro TLA() = #externalMacro(module: "SwiftTLAPlugin", type: "AttachedTLASpecMacro")
