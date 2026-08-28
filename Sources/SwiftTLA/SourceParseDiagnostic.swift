import Foundation
import SwiftSyntax

/// The source range attached to a compiler diagnostic.
public struct CompilerSourceSpan: Sendable, Hashable, CustomStringConvertible {
    public enum Location: Sendable, Hashable, CustomStringConvertible {
        case utf8Offset(Int)
        case unavailable

        public var description: String {
            switch self {
            case .utf8Offset(let offset): return "UTF-8 offset \(offset)"
            case .unavailable: return "source offset unavailable"
            }
        }
    }

    public let location: Location
    public let utf8Length: Int

    public init(location: Location, utf8Length: Int) {
        self.location = location
        self.utf8Length = utf8Length
    }

    public var description: String {
        "\(location), length \(utf8Length)"
    }
}

/// Parser facts used to emit a source compiler diagnostic.
package struct SourceParseDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    package let message: String
    package let source: String
    package let sourceSpan: CompilerSourceSpan
    package let expected: String
    package let actual: String
    package let nextSafeAction: String
    package let capabilityDiagnostic: LanguageCapabilityDiagnostic?

    init(
        message: String,
        source: String,
        expected: String = "a supported SwiftTLA declaration or expression",
        actual: String = "",
        nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again."
    ) {
        self.init(
            message: message,
            source: source,
            sourceSpan: CompilerSourceSpan(location: .unavailable, utf8Length: source.utf8.count),
            expected: expected,
            actual: actual,
            nextSafeAction: nextSafeAction
        )
    }

    init(
        message: String,
        source: String,
        sourceSpan: CompilerSourceSpan,
        expected: String = "a supported SwiftTLA declaration or expression",
        actual: String = "",
        nextSafeAction: String = "Rewrite this source fragment using the supported SwiftTLA builder form, then compile again.",
        capabilityDiagnostic: LanguageCapabilityDiagnostic? = nil
    ) {
        self.message = message
        self.source = source
        self.sourceSpan = sourceSpan
        self.expected = expected
        self.actual = actual.isEmpty ? source.trimmingCharacters(in: .whitespacesAndNewlines) : actual
        self.nextSafeAction = nextSafeAction
        self.capabilityDiagnostic = capabilityDiagnostic
    }

    init(capability: LanguageCapabilityDiagnostic) {
        self.init(
            message: capability.headline,
            source: capability.source,
            sourceSpan: capability.sourceSpan,
            expected: capability.expected,
            actual: capability.actual,
            nextSafeAction: capability.nextSafeAction,
            capabilityDiagnostic: capability
        )
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
            message: message,
            source: fragment,
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
        capabilityDiagnostic?.description ?? message
    }

    package var description: String {
        if let capabilityDiagnostic {
            return capabilityDiagnostic.description
        }
        return "What failed: \(message) Where: \(sourceSpan). Expected: \(expected). "
            + "Actual: \(actual). "
            + "Next safe action: \(nextSafeAction)"
    }
}
