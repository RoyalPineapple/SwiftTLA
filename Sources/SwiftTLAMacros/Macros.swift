@freestanding(declaration, names: named(TLA))
public macro TLASpec(_ body: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: named(Action), named(initial), named(transitions), named(availableActions), named(apply))
public macro TLA() = #externalMacro(module: "SwiftTLAPlugin", type: "AttachedTLASpecMacro")

@attached(member, names: named(Action), named(initial))
public macro TLASpec() = #externalMacro(module: "SwiftTLAPlugin", type: "TLASpecAttachedMacro")
