/// Checks the source-to-compiled constructor and ordered operand link used by
/// the finite Boolean-tree semantic proof. Leaf expressions have separate rules.
package enum BooleanBranchLoweringContract {
    package static func matches(
        source: StateExpr,
        loweredOperands: [CompiledExpression],
        result: CompiledExpression
    ) -> Bool {
        let expected: CompiledOperation
        let arity: Int
        switch source {
        case .not:
            expected = .not
            arity = 1
        case .and:
            expected = .and
            arity = 2
        case .or:
            expected = .or
            arity = 2
        case .ifThenElse:
            expected = .ifThenElse
            arity = 3
        default:
            return false
        }
        return loweredOperands.count == arity
            && result.operation == expected
            && result.children.count == arity
            && zip(result.children, loweredOperands).allSatisfy {
                $0.hasSameOccurrence(as: $1)
            }
    }
}
