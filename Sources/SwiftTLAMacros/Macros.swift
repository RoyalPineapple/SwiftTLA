@freestanding(declaration, names: named(Spec))
public macro spec(_ body: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "ModelMacro")

@attached(member, names: named(Action), named(initial))
public macro TLASpec() = #externalMacro(module: "SwiftTLAPlugin", type: "TLASpecAttachedMacro")
