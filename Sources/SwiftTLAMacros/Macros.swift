@freestanding(declaration, names: named(VerifiedStateMachine))
public macro VerifiedStateMachine(_ spec: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "VerifiedStateMachineMacro")
