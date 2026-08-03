@freestanding(declaration, names: named(TLA))
public macro TLA(_ spec: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "VerifiedStateMachineMacro")

@attached(member, names: named(Action), named(initial))
public macro TLASpec() = #externalMacro(module: "SwiftTLAPlugin", type: "TLASpecAttachedMacro")
