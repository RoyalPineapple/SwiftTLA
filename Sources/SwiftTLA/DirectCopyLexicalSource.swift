/// Source inputs retained by the compiler while parsing a registered direct-copy Algorithm.
package struct DirectCopyLexicalSource: Codable, Equatable, Sendable {
    package struct Span: Codable, Equatable, Sendable {
        /// UTF-8 offset from the opening brace of the selected #spec closure.
        package let offset: Int
        package let length: Int

        package init(offset: Int, length: Int) {
            self.offset = offset
            self.length = length
        }
    }

    package struct Token: Codable, Equatable, Sendable {
        package let name: String
        package let span: Span

        package init(name: String, span: Span) {
            self.name = name
            self.span = span
        }
    }

    package struct Literal: Codable, Equatable, Sendable {
        package let value: String
        package let span: Span

        package init(value: String, span: Span) {
            self.value = value
            self.span = span
        }
    }

    package struct Label: Codable, Equatable, Sendable {
        package let enumName: Token
        package let caseName: Token

        package init(enumName: Token, caseName: Token) {
            self.enumName = enumName
            self.caseName = caseName
        }
    }

    package struct Copy: Codable, Equatable, Sendable {
        package let target: Token
        package let read: Token

        package init(target: Token, read: Token) {
            self.target = target
            self.read = read
        }
    }

    package enum Event: Codable, Equatable, Sendable {
        case shared(binding: Token, explicit: Literal?)
        case alias(binding: Token, source: Token)
        case step(label: Label, copies: [Copy])
    }

    package let algorithm: Token
    package let registration: Token
    package let events: [Event]

    package init(algorithm: Token, registration: Token, events: [Event]) {
        self.algorithm = algorithm
        self.registration = registration
        self.events = events
    }
}
