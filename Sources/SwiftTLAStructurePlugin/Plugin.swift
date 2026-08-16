import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct SwiftTLAStructurePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StateExprStructuralMacro.self
    ]
}
