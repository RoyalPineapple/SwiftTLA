import Testing
@testable import SwiftTLA

struct ActionDomainTests {
    @Test("action domains retain parameter bindings through enumeration")
    func enumeratesConfiguredDomain() throws {
        let reference = ParameterReference(name: "limit")
        var spec = canonicalTestSpec(variables: [("value", .value(.int(0)))],
            actions: [("select", .assign(.named("value"), .variable("member")),
                [ActionBinding(name: "member", values: [.int(1), .int(2), .int(3)])])])
        spec.parameters = [.init(reference: reference, swiftType: "Int",
            domain: .integerRange(.int(0), .int(3)))]
        let compilation = try spec.compile()
        let parameter = try #require(compilation.layout.parameters.first)
        let original = try #require(compilation.semantics.behavior.actions.first)
        let binding = try #require(original.bindings.first)
        let domain = CompiledExpression(operation: .integerRange, resultType: .set(.int), children: [
            .init(operation: .value(.integer(1)), resultType: .int, children: []),
            .init(operation: .boundValue(parameter.binder), resultType: .int, children: [])
        ])
        let action = CompiledAction(id: original.id,
            bindings: [.init(binder: binding.binder, sourceName: binding.sourceName,
                domain: domain, generatedSwiftType: "Int")], body: original.body, collection: nil)
        let initial = try CompiledState(values: [.integer(0)], layout: compilation.layout, identity: compilation.identity)
        let variable = try #require(compilation.layout.testVariableID(named: "value"))
        #expect(action.bindings[0].literalMembers == nil)
        #expect(action.bindings[0].domain == domain)
        for limit in [0, 1, 3] {
            let enumerator = CompiledActionEnumerator(state: initial) { expression, bindings in
                try CompiledEvaluator(state: initial, operators: compilation.semantics.operators,
                    bindings: bindings.binding(.integer(limit), to: parameter.binder)).evaluate(expression)
            }
            let successors = try enumerator.enumerateSuccessors(action)
            #expect(successors.count == limit)
            #expect(successors.map(\.arguments) == (0..<limit).map { [.integer($0 + 1)] })
            #expect(try successors.map { try $0.state.value(for: variable) } == (0..<limit).map { .integer($0 + 1) })
        }
        let transformed = action.map { expression in
            expression == domain ? .init(operation: .value(.integer(1)), resultType: .int, children: []) : expression
        }
        let invalid = CompiledActionEnumerator(state: initial) { expression, bindings in
            try CompiledEvaluator(state: initial, operators: compilation.semantics.operators,
                bindings: bindings).evaluate(expression)
        }
        #expect(throws: EvalError.expected(.set, actual: [.integer(1)])) {
            try invalid.enumerate(transformed)
        }
    }
}
