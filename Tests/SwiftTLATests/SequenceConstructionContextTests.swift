import Testing
@testable import SwiftTLA

@Suite struct SequenceConstructionContextTests {
    @Test("Sequence construction resolves empty accumulator fields from their new elements")
    func emptyAccumulatorField() throws {
        let storedItems = StateExpr.recordAccess(.variable("accumulator"), "items")
        let constructions: [StateExpr] = [
            .tupleAppend(storedItems, .int(1)),
            .tupleConcatenate(storedItems, .tupleLiteral([.int(1)]))
        ]
        for items in constructions {
            let operation = FormalOperatorDefinition(name: "Extend", parameters: [.value("accumulator")],
                body: .recordLiteral(.init(["items": items])))
            let call = StateExpr.operatorApplication(.reference("Extend", arity: 1), [
                .value(.recordLiteral(.init(["items": .tupleLiteral([])])))
            ])
            let specification = TLASpec(name: "SequenceContext", variables: [], actions: [],
                invariants: [.init(name: "Count", body: .equal(
                    .tupleLength(.recordAccess(call, "items")), .int(1)))],
                formalOperatorDefinitions: [operation])
            let program = try NativeResolvedProgram(plan: .init(compilation: specification.compile()))
            let function = try #require(program.functions.first)
            #expect(function.parameterTypes == [.record([.init(name: "items", type: .array(.int))])])
        }
    }
}
