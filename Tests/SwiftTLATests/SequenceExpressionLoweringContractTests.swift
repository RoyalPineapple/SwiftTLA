import Testing
@testable import SwiftTLA

@Suite("Sequence expression lowering preserves source structure")
struct SequenceExpressionLoweringContractTests {
    @Test("Each sequence edit retains its operation and ordered operands")
    func acceptedConstructors() {
        let sequence = StateExpr.variable("sequence")
        let argument = StateExpr.variable("argument")
        let left = CompiledExpression(operation: .checkingLevel, children: [])
        let right = CompiledExpression(operation: .checkingDiameter, children: [])
        let operands = [left, right]
        let cases: [(StateExpr, CompiledOperation)] = [
            (.tupleAppend(sequence, argument), .tupleAppend),
            (.tupleConcatenate(sequence, argument), .tupleConcatenate),
            (.tupleRemoving(sequence, argument), .tupleRemoving),
            (.tuplePrefix(sequence, argument), .tuplePrefix)
        ]
        for (source, operation) in cases {
            #expect(SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: operation, children: operands)))
            #expect(!SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: .tupleLength, children: operands)))
            #expect(!SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: operation, children: [right, left])))
            #expect(!SequenceExpressionLoweringContract.matches(source: source,
                loweredOperands: operands,
                result: .init(operation: operation, children: [left])))
        }
    }
}
