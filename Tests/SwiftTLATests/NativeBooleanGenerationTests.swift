import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Generated boolean predicates retain lazy statement boundaries")
struct NativeBooleanGenerationTests {
    @Test("Nested predicates emit typed statements and guard the right operand")
    func booleanStatements() throws {
        let source = Parser.parse(source: """
        struct NestedPredicates {
            enum Step: String, CaseIterable { case advance }
            static var spec: TLASpec {
                #spec("NestedPredicates") {
                    Algorithm("NestedPredicates", scoped: { scope in
                        let count = scope.sharedVar("count", initial: 0)
                        Do(Step.advance) {
                            When((count < 3 && count >= 0) || count == 10)
                            Assign(count, to: count + 1)
                        }
                    })
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        let generated = try MacroExpander.generateStateMachineMembers(model: model).map(\.description).joined(separator: "\n")
        #expect(generated.contains("let _leftPredicate: Bool"))
        #expect(generated.contains("guard _leftPredicate else"))
        #expect(generated.contains("guard !_leftPredicate else"))
        #expect(generated.contains("let _rightPredicate: Bool"))
        #expect(!Parser.parse(source: "struct Expansion {\n\(generated)\n}").hasError)
    }

}
