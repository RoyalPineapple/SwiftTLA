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
        #expect(rendered.contains("text = \(literal)"))
    }
}
