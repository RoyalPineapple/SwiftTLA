import Testing
@testable import SwiftTLAPlugin
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@Suite(.serialized) struct DefinePhaseGeneratedModelTests {
    @Test("#spec retains definitions in the authored PlusCal define section")
    func keepsDefinePhaseDeclaration() throws {
        let plusCal = try DefinePhaseGeneratedModel.spec.compile().render().plusCalBundle().root.tla
        let define = try #require(plusCal.range(of: "define {"))
        let visible = try #require(plusCal.range(of: "Visible == TRUE"))
        #expect(define.lowerBound < visible.lowerBound)
    }
}
