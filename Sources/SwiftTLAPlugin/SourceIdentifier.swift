import SwiftSyntax

extension TokenSyntax {
    /// The declaration identity, without source-only backtick escaping.
    package var sourceIdentifierName: String { identifier?.name ?? text }
}
