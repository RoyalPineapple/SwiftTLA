import Testing
@testable import SwiftTLA

@Suite("Boolean branch lowering preserves source structure")
struct BooleanBranchLoweringContractTests {
    @Test("Every branch constructor retains its operation and ordered operands")
    func acceptedConstructors() {
        let first = CompiledExpression(operation: .checkingLevel, children: [])
        let second = CompiledExpression(operation: .checkingDiameter, children: [])
        let third = CompiledExpression(operation: .integerSet, children: [])
        let yes = StateExpr.value(.bool(true))
        let no = StateExpr.value(.bool(false))
        let cases: [(StateExpr, CompiledOperation, [CompiledExpression])] = [
            (.not(yes), .not, [first]),
            (.and(yes, no), .and, [first, second]),
            (.or(yes, no), .or, [first, second]),
            (.ifThenElse(yes, no, yes), .ifThenElse, [first, second, third])
        ]
        for (source, operation, operands) in cases {
            let result = CompiledExpression(operation: operation, children: operands)
            #expect(BooleanBranchLoweringContract.matches(source: source,
                loweredOperands: operands, result: result))
        }
    }

    @Test("A changed operation, missing child, or reversed order breaks the link")
    func rejectsMutations() {
        let left = CompiledExpression(operation: .checkingLevel, children: [])
        let right = CompiledExpression(operation: .checkingDiameter, children: [])
        let source = StateExpr.and(.value(.bool(true)), .value(.bool(false)))
        let operands = [left, right]
        #expect(!BooleanBranchLoweringContract.matches(source: source,
            loweredOperands: operands,
            result: .init(operation: .or, children: operands)))
        #expect(!BooleanBranchLoweringContract.matches(source: source,
            loweredOperands: operands,
            result: .init(operation: .and, children: [left])))
        #expect(!BooleanBranchLoweringContract.matches(source: source,
            loweredOperands: operands,
            result: .init(operation: .and, children: [right, left])))
    }
}
