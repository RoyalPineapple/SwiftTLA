@freestanding(declaration)
public macro VerifiedStateMachine(_ spec: () -> Void) = #externalMacro(module: "SwiftTLAMacros", type: "VerifiedStateMachineMacro")
