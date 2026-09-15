import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ActionDomainTests {
    @Test("enabled-action dependencies in domains determine evaluation order")
    func ordersDomainDependencies() throws {
        let spec = canonicalTestSpec(variables: [("value", .value(.int(0)))], actions: [
            ("select", .assign(.named("value"), .variable("member")), [
                ActionBinding(name: "member", domain: .ifThenElse(.enabledAction("ready"),
                    .setLiteral([.int(1)]), .setLiteral([])), generatedSwiftType: "Int")
            ]),
            ("ready", .guard_(.value(.bool(true))), [])
        ])
        let compilation = try spec.compile()
        let behavior = compilation.semantics.behavior
        #expect(behavior.enabledActionIndices == [1, 0])
        #expect(behavior.enabledActionDependencies[behavior.actions[0].id] == [behavior.actions[1].id])
    }

    @Test("enabled-action cycles through domains fail compilation")
    func rejectsDomainCycle() throws {
        let spec = canonicalTestSpec(variables: [("value", .value(.int(0)))], actions: [
            ("select", .assign(.named("value"), .variable("member")), [
                ActionBinding(name: "member", domain: .ifThenElse(.enabledAction("select"),
                    .setLiteral([.int(1)]), .setLiteral([])), generatedSwiftType: "Int")
            ])
        ])
        do {
            _ = try spec.compile()
            Issue.record("Expected a cyclic action-domain dependency diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .cyclicActionEnabledness)
        }
    }

    @Test("an action binding is not in scope in its own domain")
    func rejectsSelfReference() throws {
        let spec = canonicalTestSpec(variables: [("value", .value(.int(0)))],
            actions: [("select", .assign(.named("value"), .variable("member")),
                [ActionBinding(name: "member", domain: .variable("member"), generatedSwiftType: "Int")])])
        #expect(throws: CompilationDiagnostic.self) { try spec.compile() }
    }

    @Test("an action domain must have the declared member type")
    func rejectsIncompatibleDomain() throws {
        let spec = canonicalTestSpec(variables: [("value", .value(.int(0)))],
            actions: [("select", .assign(.named("value"), .variable("member")),
                [ActionBinding(name: "member", domain: .integerRange(.int(1), .int(3)),
                    generatedSwiftType: "Bool")])])
        let compilation = try spec.compile()
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        }
    }

    @Test("action domains retain parameter bindings through enumeration")
    func enumeratesConfiguredDomain() throws {
        let reference = ParameterReference(name: "limit")
        var spec = canonicalTestSpec(variables: [("value", .value(.int(0)))],
            actions: [("select", .assign(.named("value"), .variable("member")),
                [ActionBinding(name: "member", domain: .integerRange(.int(1), .parameter(reference)),
                    generatedSwiftType: "Int")])])
        spec.parameters = [.init(reference: reference, swiftType: "Int",
            domain: .integerRange(.int(0), .int(3)))]
        let compilation = try spec.compile()
        let parameter = try #require(compilation.layout.parameters.first)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let action = try #require(program.behavior.actions.first)
        let domain = try #require(action.bindings.first).domain
        #expect(domain.operation == .integerRange)
        #expect(domain.resultType == .set(.int))
        #expect(domain.children.map(\.resultType) == [.int, .int])
        #expect(domain.children.last?.operation == .boundValue(parameter.binder))
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
