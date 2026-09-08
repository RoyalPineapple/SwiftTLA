import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Record construction retains compiled field evaluation order")
struct NativeRecordEvaluationOrderTests {
    @Test("Field expressions run once in source order before canonical construction")
    func orderedFields() throws {
        let formal = StateExpr.recordLiteral(.init(orderedFields: [
            .init(name: "z", value: .divide(.int(1), .int(0))),
            .init(name: "a", value: .negate(.int(Int.min)))
        ]))
        #expect(throws: EvalError.divisionByZero) { try evaluateClosed(formal) }
        let source = Parser.parse(source: """
        struct RecordOrder {
            enum Step: String, CaseIterable { case advance }
            static var spec: TLASpec {
                #spec("RecordOrder") {
                    Algorithm("RecordOrder", scoped: { scope in
                        let count = scope.sharedVar("count", initial: 0)
                        Do(Step.advance) { Assign(count, to: count + 1) }
                    })
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = try NativeSwiftEmitter(model: model)
        let expression = CompiledStateExpr.recordLiteral(.init([
            .init(id: .init(ordinal: 0), key: .string("z"), value: .divide(.value(.integer(1)), .value(.integer(0)))),
            .init(id: .init(ordinal: 1), key: .string("a"), value: .negate(.value(.integer(Int.min))))
        ]))
        let generated = try emitter.expression(expression)
        let first = try #require(generated.range(of: "let _recordField0"))
        let second = try #require(generated.range(of: "let _recordField1"))
        let division = try #require(generated.range(of: "_NativeMachineOperations.divide"))
        let overflow = try #require(generated.range(of: "_NativeMachineOperations.negate"))
        #expect(first.lowerBound < division.lowerBound)
        #expect(division.lowerBound < second.lowerBound)
        #expect(second.lowerBound < overflow.lowerBound)
        #expect(generated.contains("`a`: _recordField1, `z`: _recordField0"))
        #expect(generated.components(separatedBy: "_NativeMachineOperations.divide").count == 2)
        #expect(generated.components(separatedBy: "_NativeMachineOperations.negate").count == 2)
        #expect(!Parser.parse(source: "let value = \(generated)").hasError)
    }
}
