@freestanding(declaration)
public macro VerifiedStateMachine(_ spec: () -> Void) = #externalMacro(module: "SwiftTLAPlugin", type: "VerifiedStateMachineMacro")
