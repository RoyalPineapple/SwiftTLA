@testable import SwiftTLA
import Testing

@Suite struct FormalOperatorRecursionTests {
    @Test("self-recursive formal calls stop at the existing depth limit")
    func boundsSelfRecursion() {
        let operation = FormalOperatorDefinition(
            name: "Loop", parameters: [.value("item")],
            body: .operatorApplication(.reference("Loop", arity: 1), [.value(.variable("item"))])
        )
        #expect(throws: EvalError.recursionDepthExceeded(4_096)) {
            try compiledValue(
                .operatorApplication(.reference("Loop", arity: 1), [.value(.int(0))]),
                formalOperators: [operation]
            )
        }
    }

    @Test("mutually recursive formal calls share the depth limit")
    func boundsMutualRecursion() {
        let operations: [FormalOperatorDefinition] = [
            .init(name: "First", parameters: [], body: .operatorApplication(.reference("Second", arity: 0), [])),
            .init(name: "Second", parameters: [], body: .operatorApplication(.reference("First", arity: 0), []))
        ]
        #expect(throws: EvalError.recursionDepthExceeded(4_096)) {
            try compiledValue(.operatorApplication(.reference("First", arity: 0), []), formalOperators: operations)
        }
    }

    @Test("completed calls release depth for later independent calls")
    func completedCallsReleaseDepth() throws {
        let operation = FormalOperatorDefinition(
            name: "CountDown", parameters: [.value("item")], body: .ifThenElse(
                .lessOrEqual(.variable("item"), .int(0)), .int(0),
                .operatorApplication(.reference("CountDown", arity: 1), [
                    .value(.subtract(.variable("item"), .int(1)))
                ])
            )
        )
        let call = StateExpr.operatorApplication(.reference("CountDown", arity: 1), [.value(.int(64))])
        let calls = Array(repeating: call, count: 65)
        #expect(try compiledValue(.tupleLiteral(calls), formalOperators: [operation]) == .tuple(Array(repeating: .int(0), count: 65)))
    }

    @Test("deep evaluated arguments preserve results and the shared lambda call limit")
    func boundsCallsThroughLambdas() throws {
        let operation = FormalOperatorDefinition(
            name: "CountDown", parameters: [.value("remaining")], body: .ifThenElse(
                .equal(.variable("remaining"), .int(0)), .int(0),
                .operatorApplication(.lambda(.init(parameters: ["next"], body:
                    .operatorApplication(.reference("CountDown", arity: 1), [.value(.variable("next"))])
                )), [.value(.subtract(.variable("remaining"), .int(1)))])
            )
        )
        func countDown(from value: Int) throws -> TLAValue {
            try compiledValue(
                .operatorApplication(.reference("CountDown", arity: 1), [.value(.int(value))]),
                formalOperators: [operation]
            )
        }
        #expect(try countDown(from: 1_000) == .int(0))
        #expect(throws: EvalError.recursionDepthExceeded(_NativeMachineOperations.maximumRecursiveDepth)) {
            try countDown(from: 2_050)
        }
    }
}
