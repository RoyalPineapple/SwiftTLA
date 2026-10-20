/// Checks the source-to-compiled constructor and ordered operand link for sequence edits.
package enum SequenceExpressionLoweringContract {
    package static func matches(
        source: StateExpr,
        loweredOperands: [CompiledExpression],
        result: CompiledExpression
    ) -> Bool {
        let expected: CompiledOperation
        switch source {
        case .tupleAppend: expected = .tupleAppend
        case .tupleConcatenate: expected = .tupleConcatenate
        case .tupleRemoving: expected = .tupleRemoving
        case .tuplePrefix: expected = .tuplePrefix
        default: return false
        }
        return loweredOperands.count == 2
            && result.operation == expected
            && result.children.count == 2
            && zip(result.children, loweredOperands).allSatisfy {
                $0.hasSameOccurrence(as: $1)
            }
    }
}
