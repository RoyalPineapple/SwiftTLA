import Foundation
import SwiftSyntax

/// The source range attached to a compiler diagnostic.
package struct CompilerSourceSpan: Sendable, Hashable, CustomStringConvertible {
    package enum Location: Sendable, Hashable, CustomStringConvertible {
        case utf8Offset(Int)
        case unavailable

        package var description: String {
            switch self {
            case .utf8Offset(let offset): return "UTF-8 offset \(offset)"
            case .unavailable: return "source offset unavailable"
            }
        }
    }

    package let location: Location
    package let utf8Length: Int

    package init(location: Location, utf8Length: Int) {
        self.location = location
        self.utf8Length = utf8Length
    }

    package var description: String {
        "\(location), length \(utf8Length)"
    }
}

/// Parser facts used to emit a source compiler diagnostic.
package struct SourceParseDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    package enum Code: String, Sendable, Hashable {
        case unsupportedLanguageConstruct = "unsupported-language-construct"
        case invalidLanguagePlacement = "invalid-language-placement"
    }

    package let code: Code?
    package let message: String
    package let source: String
    package let sourcePath: [String]
    package let sourceSpan: CompilerSourceSpan
    package let expected: String
    package let actual: String
    package let nextSafeAction: String

    init(
        message: String,
        source: String,
        expected: String = "a supported SwiftTLA declaration or expression",
        actual: String = "",
        nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
    ) {
        self.init(
            code: nil,
            message: message,
            source: source,
            sourcePath: [],
            sourceSpan: CompilerSourceSpan(location: .unavailable, utf8Length: source.utf8.count),
            expected: expected,
            actual: actual,
            nextSafeAction: nextSafeAction
        )
    }

    init(
        code: Code? = nil,
        message: String,
        source: String,
        sourcePath: [String] = [],
        sourceSpan: CompilerSourceSpan,
        expected: String = "a supported SwiftTLA declaration or expression",
        actual: String = "",
        nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
    ) {
        self.code = code
        self.message = message
        self.source = source
        self.sourcePath = sourcePath
        self.sourceSpan = sourceSpan
        self.expected = expected
        self.actual = actual.isEmpty ? source.trimmingCharacters(in: .whitespacesAndNewlines) : actual
        self.nextSafeAction = nextSafeAction
    }

    init<Node: SyntaxProtocol>(
        message: String,
        source: Node,
        expected: String = "a supported SwiftTLA declaration or expression",
        actual: String = "",
        nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
    ) {
        let fragment = source.description.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            code: nil,
            message: message,
            source: fragment,
            sourcePath: [],
            sourceSpan: CompilerSourceSpan(
                location: .utf8Offset(source.positionAfterSkippingLeadingTrivia.utf8Offset),
                utf8Length: fragment.utf8.count
            ),
            expected: expected,
            actual: actual,
            nextSafeAction: nextSafeAction
        )
    }

    package var renderedMessage: String {
        description
    }

    package var description: String {
        let codeDescription = code.map { "Code: \($0.rawValue). " } ?? ""
        let location = sourcePath.isEmpty
            ? sourceSpan.description
            : "\(sourcePath.joined(separator: ".")), \(sourceSpan)"
        return "\(codeDescription)What failed: \(message) Where: \(location). Expected: \(expected). "
            + "Actual: \(actual). "
            + "Next safe action: \(nextSafeAction)"
    }
}
