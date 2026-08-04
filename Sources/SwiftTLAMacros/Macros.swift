@freestanding(declaration, names: named(TLAStateMachine))
public macro TLASpec(_ body: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: named(Action), named(initial), named(transitions), named(availableActions), named(apply))
public macro TLA() = #externalMacro(module: "SwiftTLAPlugin", type: "AttachedTLASpecMacro")
