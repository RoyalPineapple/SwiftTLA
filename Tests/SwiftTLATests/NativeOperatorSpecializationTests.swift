import Testing
@testable import SwiftTLA

@Suite struct NativeOperatorSpecializationTests {
    @Test("one formal operator preserves independent integer and string call evidence")
    func separateArgumentShapes() throws {
        let compilation = try specification(body: .variable("value")).compile()
        let plan = NativeMachinePlan(compilation: compilation)
        let inference = try NativeTypeInference(plan: plan)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let integer = try inference.operatorCall(operation.id, arguments: [.value(.value(.integer(1)))], expected: .int)
        let string = try inference.operatorCall(operation.id, arguments: [.value(.value(.string("a")))], expected: .string)
        #expect(integer.result == .int)
        #expect(string.result == .string)
        #expect(integer.specialization != string.specialization)
        let parameter = try #require(integer.parameters.first)
        #expect(integer.inference.bindings[parameter] == .int)
        #expect(string.inference.bindings[parameter] == .string)
        #expect(inference.bindings[parameter] == nil)
    }

    @Test("local operators capture the enclosing typed specialization independently")
    func separateLexicalCaptures() throws {
        let compilation = try specification(body: .letIn([
            .init("Captured", parameters: [], body: .variable("value"))
        ], .recursiveCall("Captured", []))).compile()
        let plan = NativeMachinePlan(compilation: compilation)
        let inference = try NativeTypeInference(plan: plan)
        let operation = try #require(plan.formalOperatorDefinitions.first)
        let integer = try inference.operatorCall(operation.id, arguments: [.value(.value(.integer(1)))], expected: .int)
        let string = try inference.operatorCall(operation.id, arguments: [.value(.value(.string("a")))], expected: .string)
        #expect(integer.result == .int)
        #expect(string.result == .string)
        #expect(try integer.inference.type(of: integer.body, expected: .int) == .int)
        #expect(try string.inference.type(of: string.body, expected: .string) == .string)
    }

    @Test("filter and CHOOSE retain nominal evidence established by their predicates")
    func selectionResultKeepsPredicateEvidence() throws {
        let domain = StateExpr.setLiteral([.value(.string("read"))])
        let predicate = StateExpr.equal(.variable("candidate"), .variable("selected"))
        let filter = StateExpr.setFilter(domain, "candidate", predicate)
        let choice = StateExpr.choose(domain, "candidate", predicate)
        let compilation = try TLASpec(
            name: "SelectionResultEvidence",
            variables: [.init(name: "selected", initialization: .value(.string("read")), generatedSwiftType: "Kind", origin: .compiler)],
            actions: [],
            invariants: [
                .init(name: "Filter", body: .equal(.cardinality(filter), .int(1))),
                .init(name: "Choice", body: .equal(.cardinality(.setLiteral([choice])), .int(1))),
            ]
        ).compile()
        let plan = NativeMachinePlan(compilation: compilation)
        let inference = try NativeTypeInference(plan: plan, sourceTypes: .init(enums: ["Kind": [.string("read")]]))
        guard case .equal(.cardinality(let filtered), _) = plan.invariants[0].body,
              case .equal(.cardinality(.setLiteral(let choices)), _) = plan.invariants[1].body else {
            Issue.record("Expected selection fixture expressions")
            return
        }
        let selected = try #require(choices.first)
        #expect(try inference.type(of: filtered, expected: .set(.string)) == .set(.named("Kind")))
        #expect(try inference.type(of: selected, expected: .string) == .named("Kind"))
    }

    private func specification(body: StateExpr) -> TLASpec {
        TLASpec(
            name: "PolymorphicCalls",
            variables: [
                .init(name: "number", initialization: .value(.int(0)), origin: .compiler),
                .init(name: "text", initialization: .value(.string("")), origin: .compiler),
            ],
            actions: [.init(name: "step", body: .and(
                .assign(.named("number"), .operatorApplication(.reference("Identity", arity: 1), [.value(.int(1))])),
                .assign(.named("text"), .operatorApplication(.reference("Identity", arity: 1), [.value(.value(.string("a")))]))
            ))],
            invariants: [],
            formalOperatorDefinitions: [.init(name: "Identity", parameters: [.value("value")], body: body)]
        )
    }
}
