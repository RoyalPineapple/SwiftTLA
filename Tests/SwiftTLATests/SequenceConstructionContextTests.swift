@testable import SwiftTLAPlugin
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
            let program = try NativeResolvedProgram(compilation: specification.compile())
            let function = try #require(program.functions.first)
            #expect(function.parameterTypes == [.record([.init(name: "items", type: .array(.int))])])
        }
    }

    @Test("Recursive folds carry the resolved accumulator type into their empty base value")
    func recursiveFoldAccumulator() throws {
        let append = FormalOperatorDefinition(name: "AppendItem", parameters: [.value("item"), .value("accumulator")],
            body: .recordLiteral(.init(["items": .tupleAppend(
                .recordAccess(.variable("accumulator"), "items"), .variable("item"))])))
        let fold = StateExpr.operatorApplication(.reference("FoldFunction", arity: 3), [
            .operator(.reference("AppendItem", arity: 2)),
            .value(.recordLiteral(.init(["items": .tupleLiteral([])]))),
            .value(.tupleLiteral([.int(1), .int(2)]))
        ])
        let specification = TLASpec(name: "FoldContext", variables: [], actions: [],
            invariants: [.init(name: "Count", body: .equal(
                .tupleLength(.recordAccess(fold, "items")), .int(2)))],
            formalOperatorDefinitions: [append], imports: [FunctionsModule.module])
        let program = try NativeResolvedProgram(compilation: specification.compile())
        let accumulator = NativeType.record([.init(name: "items", type: .array(.int))])
        #expect(program.functions.contains { $0.parameterTypes.contains(accumulator) })
    }

    @Test("A fold refines an empty accumulator captured by a surrounding collection mapping")
    func capturedFoldAccumulator() throws {
        let append = FormalOperatorDefinition(name: "AppendItem", parameters: [.value("item"), .value("accumulator")],
            body: .recordLiteral(.init(["items": .tupleAppend(
                .recordAccess(.variable("accumulator"), "items"), .variable("item"))])))
        let fold = StateExpr.operatorApplication(.reference("FoldFunction", arity: 3), [
            .operator(.reference("AppendItem", arity: 2)),
            .value(.variable("initial")), .value(.variable("sequence"))
        ])
        let results = StateExpr.letValue("initial", .recordLiteral(.init(["items": .tupleLiteral([])])),
            .setMap(fold, "sequence", .setLiteral([.tupleLiteral([.int(1), .int(2)])])))
        let specification = TLASpec(name: "CapturedFoldContext", variables: [], actions: [],
            invariants: [.init(name: "Count", body: .forAll(results, "result", .equal(
                .tupleLength(.recordAccess(.variable("result"), "items")), .int(2))))],
            formalOperatorDefinitions: [append], imports: [FunctionsModule.module])
        let program = try NativeResolvedProgram(compilation: specification.compile())
        let accumulator = NativeType.record([.init(name: "items", type: .array(.int))])
        #expect(program.functions.contains { $0.parameterTypes.contains(accumulator) })
    }
}
