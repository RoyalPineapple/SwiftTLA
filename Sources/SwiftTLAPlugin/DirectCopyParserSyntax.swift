import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

struct DirectCopyParserSyntax {
    typealias Copy = (target: TokenSyntax, read: TokenSyntax)
    typealias CopyObserver = (Copy) -> Void

    enum Event {
        case shared(binding: TokenSyntax, explicit: (syntax: StringLiteralExprSyntax, value: String)?)
        case alias(binding: TokenSyntax, source: TokenSyntax)
        case step(enumName: TokenSyntax, caseName: TokenSyntax, copies: [Copy])
    }

    let binding: TokenSyntax
    let events: [Event]

    func registered(at registration: TokenSyntax, in closure: ClosureExprSyntax) -> DirectCopyLexicalSource {
        let origin = closure.positionAfterSkippingLeadingTrivia.utf8Offset
        func span(_ syntax: some SyntaxProtocol) -> DirectCopyLexicalSource.Span {
            .init(offset: syntax.positionAfterSkippingLeadingTrivia.utf8Offset - origin,
                  length: syntax.trimmedDescription.utf8.count)
        }
        func token(_ syntax: TokenSyntax) -> DirectCopyLexicalSource.Token {
            .init(name: syntax.sourceIdentifierName, span: span(syntax))
        }
        let events = self.events.map { event -> DirectCopyLexicalSource.Event in
            switch event {
            case .shared(let binding, let explicit):
                return .shared(binding: token(binding),
                               explicit: explicit.map { .init(value: $0.value, span: span($0.syntax)) })
            case .alias(let binding, let source):
                return .alias(binding: token(binding), source: token(source))
            case .step(let enumName, let caseName, let copies):
                return .step(label: .init(enumName: token(enumName), caseName: token(caseName)),
                             copies: copies.map { .init(target: token($0.target), read: token($0.read)) })
            }
        }
        return .init(algorithm: token(binding), registration: token(registration), events: events)
    }
}
