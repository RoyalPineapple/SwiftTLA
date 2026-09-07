import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

enum MacroExpander {
    static func generateStateMachineMembers(model: MacroCompilation) throws -> [DeclSyntax] {
        var emitter = try NativeSwiftEmitter(model: model)
        return try emitter.machineMembers()
    }

}
