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
            let generatedFormalUnion = Algorithm(label: "GeneratedFormalUnion") {
                Each(Node.all, scoped: { _, scope in
                    let temporary: LocalVariable<OneOf<Node, SetExpr<Node>>> = scope.localVar(_name: "temporary", initial: OneOf<Node, SetExpr<Node>>.first(.first)
                    )

                    Do(Label.inspect) {
                        let member = temporary.expr.assuming(Node.self)
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
                        let remaining = temporary.expr.assuming(SetExpr<Node>.self)
                        When(!remaining.isEmpty)
                    }
                })
            }
            generatedFormalUnion
        }
    }
}

@TLAModel
private struct RecordUnionFieldModel {
    struct Token: Hashable, Sendable {
        let type: String
        let q: Int
    }

    struct Payload: Hashable, Sendable {
        let type: String
        let src: Int
    }

    private enum Step: String, CaseIterable { case consume }

    static var spec: TLASpec {
        #spec("RecordUnionField") { scope in
            let message = scope.sharedVar(initial: OneOf<Token, Payload>.first(
                Token.expression(type: "tok", q: 1)))
            Do(Step.consume) {
                When(message.recordFields.contains("q"))
                Assign(message, to: OneOf<Token, Payload>.second(
                    Payload.expression(type: "pl", src: 2)))
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

    @Test("record-union field guards distinguish alternatives in generated execution")
    func recordUnionFieldGuard() throws {
        var machine = try RecordUnionFieldModel.makeMachine()
        #expect(try machine.isEnabled(.consume))
        _ = try machine.send(.consume)
        #expect(machine.state.message == .second(.init(type: "pl", src: 2)))
        #expect(try !machine.isEnabled(.consume))
    }
}
