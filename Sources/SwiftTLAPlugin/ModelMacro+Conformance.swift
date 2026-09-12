import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension ModelMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Swift supplies only conformances the declaration does not already have.
        // Restrict to the same struct hosts accepted by the member expansion.
        guard declaration.is(StructDeclSyntax.self), !protocols.isEmpty else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): SwiftTLA.StateMachine {}")]
    }
}
