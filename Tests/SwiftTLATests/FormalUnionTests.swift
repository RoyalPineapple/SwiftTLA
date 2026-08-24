import Testing
import SwiftTLA
import SwiftTLAMacros

private enum UnionMember: String, FiniteTLAValueDomain {
    case first
    case second

    static var defaultValue: Self { .first }
    static let finiteValues: [UnionMember] = [.first, .second]

    var tlaValue: TLAValue { .string(rawValue) }
}

@TLAModel
private struct GeneratedFormalUnionAlgorithm {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case first
        case second

        static var defaultValue: Self { .first }
        static let finiteValues = allCases

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Label: String, CaseIterable {
        case inspect
        case collect
        case finish
    }

    static var spec: TLASpec {
        #spec("GeneratedFormalUnion") {
            Algorithm("GeneratedFormalUnion") {
                Each(Node.all, scoped: { _, scope in
                    let temporary: LocalVariable<OneOf<Node, SetExpr<Node>>> = scope.localVar("temporary", initial: OneOf<Node, SetExpr<Node>>.first(.first)
                    )

                    Do(Label.inspect) {
                        let member = temporary.expr.assumingFirst(Node.self)
                        Assert(member == Node.first)
                    }
                    Do(Label.collect) {
                        Assign(
                            temporary,
                            to: OneOf<Node, SetExpr<Node>>.second(
                                SetExpr<Node>.literal(.second)
                            )
                        )
                    }
                    Do(Label.finish) {
                        let remaining = temporary.expr.assumingSecond(SetExpr<Node>.self)
                        When(!remaining.isEmpty)
                    }
                })
            }
        }
    }
}

struct FormalUnionTests {
    @Test("a formal union keeps untagged values and decodes either declared shape")
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
