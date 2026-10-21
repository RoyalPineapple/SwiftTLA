/// Checks the membership operation and child identities against scheduled operands.
package enum MembershipLoweringContract {
    package static func matches(
        source: StateExpr,
        loweredOperands: [CompiledExpression],
        result: CompiledExpression
    ) -> Bool {
        guard case .in = source else { return false }
        return loweredOperands.count == 2
            && result.operation == .in
            && result.children.count == 2
            && zip(result.children, loweredOperands).allSatisfy {
                $0.hasSameOccurrence(as: $1)
            }
    }
}
