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
        let compilation = try TLASpec(name: "OrderedRecord", variables: [
            .init(name: "record", initialization: .expression(formal), origin: .compiler)
        ], actions: [], invariants: []).compile()
        let program = try NativeResolvedProgram(compilation: compilation, sourceTypes: .init())
        let annotatedModel = MacroCompilation(typeName: model.typeName, compilation: compilation,
            enumInfos: model.enumInfos, nativeProgram: program)
        var emitter = NativeSwiftEmitter(model: annotatedModel)
        let root = try #require(program.initializations.values.first)
        let generated = try emitter.expression(root)
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
