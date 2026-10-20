import Testing
@testable import SwiftTLA

@Suite("Membership lowering preserves source structure")
struct MembershipLoweringContractTests {
    @Test("Membership retains its operation and ordered member and set operands")
    func orderedOperands() {
        let member = CompiledExpression.value(.integer(1))
        let members = CompiledExpression.setLiteral([.value(.integer(1))])
        let source = StateExpr.in(.value(.int(1)), .setLiteral([.int(1)]))
        let operands = [member, members]
        #expect(MembershipLoweringContract.matches(source: source,
            loweredOperands: operands,
            result: .init(operation: .in, children: operands)))
        #expect(!MembershipLoweringContract.matches(source: source,
            loweredOperands: operands,
            result: .init(operation: .subset, children: operands)))
        #expect(!MembershipLoweringContract.matches(source: source,
            loweredOperands: operands,
            result: .init(operation: .in, children: [members, member])))
        #expect(!MembershipLoweringContract.matches(source: source,
            loweredOperands: operands,
            result: .init(operation: .in, children: [member])))
    }
}
