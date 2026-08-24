import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftTLAPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModelMacro.self,
        FiniteEnumMacro.self,
        ValueEnumMacro.self,
        TLAActorMacro.self,
        SpecExpressionMacro.self
    ]
}
