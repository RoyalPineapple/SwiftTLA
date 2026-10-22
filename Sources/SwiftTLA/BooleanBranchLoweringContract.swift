/// Checks the compiled constructor and child identities against the lowerer's
/// scheduled operands. Source scheduling and leaf meanings remain separate obligations.
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
