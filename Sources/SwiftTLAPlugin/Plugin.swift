import SwiftCompilerPlugin
import SwiftSyntaxMacros

struct SimpleError: Error, CustomStringConvertible {
    let message: String
    init(_ msg: String) { self.message = msg }
    var description: String { message }
}

@main
struct SwiftTLAPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        ModelMacro.self,
    ]
}
