import Testing
import SwiftTLA
@testable import UpstreamParity

@Suite("Swift string formal encoding")
struct SwiftStringFormalEncodingTests {
    @Test("generated machine projection and TLA+ use the same canonical string")
    func generatedOutputsShareStringIdentity() throws {
        let token = try #require(TLAStateProjection.Token(validating: "text"))
        var machine = try StringLiteralModel.makeMachine()
        let actions = try machine.enabledActions()
        #expect(actions.count == 1)
        _ = try machine.send(try #require(actions.first))

        let expected = "quote\" slash\\ newline\n return\r tab\t form\u{c} é"
        #expect(machine.state.text == expected)
        guard case .string(let projected) = try machine.formalProjection(of: machine.snapshot).value(for: token) else {
            Issue.record("Expected a formal string state")
            return
        }
        #expect(projected.utf8.elementsEqual(expected.utf8))

        let rendered = try StringLiteralModel.spec.compile().render().tlaBundle.tla
        #expect(rendered.contains("text' = \(TLAValue.string(expected).description)"))
        #expect(rendered.contains(FormalStringEncoding.declaration))
        #expect(!rendered.contains("é"))
        #expect(try TLCValueParser.parse(TLAValue.string(expected).description)
            .decodingFormalStrings() == .string(expected))
        let expectedProjection = try TLAStateProjection(validating: [
            .init(token: token, value: .string(expected))
        ])
        #expect(try CanonicalBinaryState.encode(machine.formalProjection(of: machine.snapshot))
            == CanonicalBinaryState.encode(expectedProjection))
    }

    @Test("formal-string evidence rejects malformed encoding and keeps unmarked strings literal")
    func encodedEvidenceIsExplicit() throws {
        let encoded = try TLCValueParser.parse(#""__SwiftTLA_UTF8_V1__C3A9""#)
        #expect(encoded == .string("__SwiftTLA_UTF8_V1__C3A9"))
        #expect(try encoded.decodingFormalStrings() == .string("é"))
        #expect(throws: TLCGraphEventError.self) {
            try TLCValueParser.parse(#""__SwiftTLA_UTF8_V1__C3A""#).decodingFormalStrings()
        }
        #expect(throws: TLCGraphEventError.self) {
            try TLCValueParser.parse(#""é""#).decodingFormalStrings()
        }
    }
}
