@freestanding(declaration, names: named(TLA))
public macro TLASpec(_ body: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(peer, names: arbitrary)
public macro TLA() = #externalMacro(module: "SwiftTLAPlugin", type: "AttachedTLASpecMacro")

@attached(member, names: named(Action), named(initial))
public macro TLASpec() = #externalMacro(module: "SwiftTLAPlugin", type: "TLASpecAttachedMacro")
