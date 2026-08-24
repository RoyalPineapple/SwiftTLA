import Testing
import SwiftTLA
import SwiftTLAMacros

private enum UnionMember: String, FiniteTLAValueDomain {
    case first
    case second

    static var defaultValue: Self { .first }
    static let finiteValues: [UnionMember] = [.first, .second]
    func formalUnionRoundTrips() {
        guard case .first(.first)? = OneOf<UnionMember, SetExpr<UnionMember>>(
            formalValue: .string("first")
        ) else {
            Issue.record("A member must decode as the first declared union shape.")
            return
        }
        guard case .second(let values)? = OneOf<UnionMember, SetExpr<UnionMember>>(
            formalValue: .set([.string("second")])
        ) else {
            Issue.record("A set must decode as the second declared union shape.")
            return
        }
        #expect(values.elements == [.second])
        #expect(OneOf<UnionMember, SetExpr<UnionMember>>(formalValue: .int(1)) == nil)
    }

    @Test("#spec preserves a labeled formal-union view through both construction paths")
    func generatedAlgorithmPreservesFormalUnion() throws {
        _ = try GeneratedFormalUnionAlgorithm.spec.compile()
    }
}
