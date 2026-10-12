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
    }
}
