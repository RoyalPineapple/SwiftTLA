import Testing
@testable import SwiftTLA

struct FormalStringRenderingTests {
    @Test("TLA string literals escape syntax and preserve Unicode scalars")
    func escapedLiterals() throws {
        let value = "quote\" slash\\ newline\n return\r tab\t form\u{c} e\u{301}"
        let literal = #""quote\" slash\\ newline\n return\r tab\t form\f e"# + "\u{301}\""
        #expect(TLAValue.string(value).description.utf8.elementsEqual(literal.utf8))
        #expect(TLAValue.tuple([.string(value)]).description == "<<\(literal)>>")
        #expect(TLAValue.function([.string(value): .string(value)]).description
            == "[__tla_fn_0 \\in {\(literal)} |-> \(literal)]")

        let text = Var<String>("text")
        let specification = TLASpec("EscapedStrings") { Variable(text, value) }
        let rendered = try specification.compile().render().tlaBundle.tla
        let canonicalLiteral = TLAValue.string(value.precomposedStringWithCanonicalMapping).description
        #expect(rendered.contains("text = \(canonicalLiteral)"))
    }

    @Test("typed Swift strings have one formal value for canonical equivalents")
    func typedStringIdentity() throws {
        let composed = "\u{00E9}"
        let decomposed = "e\u{301}"
        #expect(composed == decomposed)
        #expect(composed.tlaValue == decomposed.tlaValue)
        #expect(Set([composed.tlaValue, decomposed.tlaValue]).count == 1)
        guard case .string(let encoded) = decomposed.tlaValue else {
            Issue.record("Expected a formal string")
            return
        }
        #expect(encoded.utf8.elementsEqual(composed.utf8))
        let decodedRawFormal = try #require(String(formalValue: .string(decomposed)))
        #expect(decodedRawFormal.utf8.elementsEqual(decomposed.utf8))
    }
}
