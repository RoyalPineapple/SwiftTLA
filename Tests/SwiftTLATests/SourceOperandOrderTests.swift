import Testing
@testable import SwiftTLA

@Suite("Source operand order")
struct SourceOperandOrderTests {
    @Test("Compiled children follow the authored operands")
    func compiledChildrenFollowSourceOrder() throws {
        let spec = TLASpec(
            name: "SourceOperandOrder",
            variables: [
                .init(name: "member", initial: .int(1)),
                .init(name: "members", initial: .set([.int(1)])),
                .init(name: "firstFlag", initial: .bool(true)),
                .init(name: "secondFlag", initial: .bool(false)),
                .init(name: "thirdFlag", initial: .bool(true)),
                .init(name: "leftSequence", initial: .tuple([.int(1)])),
                .init(name: "rightSequence", initial: .tuple([.int(2)]))
            ],
            actions: [],
            invariants: [
                .init(name: "Membership", body: .in(.variable("member"), .variable("members"))),
                .init(name: "Conjunction", body: .and(.variable("firstFlag"), .variable("secondFlag"))),
                .init(name: "Disjunction", body: .or(.variable("firstFlag"), .variable("secondFlag"))),
                .init(name: "Conditional", body: .ifThenElse(.variable("firstFlag"),
                    .variable("secondFlag"), .variable("thirdFlag"))),
                .init(name: "Concatenation", body: .equal(
                    .tupleConcatenate(.variable("leftSequence"), .variable("rightSequence")),
                    .value(.tuple([.int(1), .int(2)]))))
            ]
        )
        let compilation = try spec.compile()
        let predicates = Dictionary(uniqueKeysWithValues: compilation.semantics.behavior.invariants.map {
            ($0.name, $0.predicate.expression.computation)
        })
        func variable(_ name: String) throws -> CompiledOperation {
            .stateVariable(try #require(compilation.layout.testVariableID(named: name)))
        }

        let membership = try #require(predicates["Membership"])
        #expect(membership.operation == .in)
        #expect(try membership.children.map(\.computation.operation) == [variable("member"), variable("members")])

        for (name, operation) in [("Conjunction", CompiledOperation.and), ("Disjunction", .or)] {
            let expression = try #require(predicates[name])
            #expect(expression.operation == operation)
            #expect(try expression.children.map(\.computation.operation)
                == [variable("firstFlag"), variable("secondFlag")])
        }

        let conditional = try #require(predicates["Conditional"])
        #expect(conditional.operation == .ifThenElse)
        #expect(try conditional.children.map(\.computation.operation)
            == [variable("firstFlag"), variable("secondFlag"), variable("thirdFlag")])

        let equality = try #require(predicates["Concatenation"])
        let concatenation = try #require(equality.children.first?.computation)
        #expect(concatenation.operation == .tupleConcatenate)
        #expect(try concatenation.children.map(\.computation.operation)
            == [variable("leftSequence"), variable("rightSequence")])
    }
}
