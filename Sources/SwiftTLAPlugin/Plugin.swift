import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftTLAPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModelMacro.self,
        TLAActorMacro.self,
        TLAObservableMacro.self,
        TLAValidatedMacro.self,
        TypedVarMacro.self,
    ]
}
