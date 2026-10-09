import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ResolvedFunctionRenderingTests {
    @Test("recursive helpers pass transitive state and guard captures explicitly without name capture")
    func rendersExplicitStateCaptures() throws {
        let compilation = try TLASpec(name: "Captures", variables: [
            .init(name: "count", initial: .int(0)), .init(name: "limit", initial: .int(3))
        ], actions: [], invariants: []).compile()
        let count = VariableID(ordinal: 0)
        let limit = VariableID(ordinal: 1)
        let countRead = CompiledExpression(operation: .stateVariable(count), resultType: .int, children: [])
        let limitRead = CompiledExpression(operation: .stateVariable(limit), resultType: .int, children: [])
        let first = CompiledExpression(operation: .call(.init(ordinal: 0)), resultType: .int, children: [])
        let second = CompiledExpression(operation: .call(.init(ordinal: 1)), resultType: .int, children: [])
        let renderer = CompiledTLARenderer(moduleName: "Captures", reservedNames: ["__Captures_state0"],
            layout: compilation.layout, bindings: .init(), operators: .init(), actions: [], functions: [
                .init(parameters: [], resultType: .int, body: second, domainGuard: nil),
                .init(parameters: [], resultType: .int,
                    body: .init(operation: .add, resultType: .int, children: [countRead, first]),
                    domainGuard: .init(operation: .lessThan, resultType: .bool, children: [countRead, limitRead]))
            ])
        #expect(try renderer.resolvedFunctionDefinitions() == [
            "RECURSIVE __Captures_resolvedFunction0(_, _), __Captures_resolvedFunction1(_, _)",
            "__Captures_resolvedFunction0(__Captures_state0_, __Captures_state1) == __Captures_resolvedFunction1(__Captures_state0_, __Captures_state1)",
            "__Captures_resolvedFunction1(__Captures_state0_, __Captures_state1) == CASE (__Captures_state0_ < __Captures_state1) -> ((__Captures_state0_ + __Captures_resolvedFunction0(__Captures_state0_, __Captures_state1)))"
        ])
        #expect(try renderer.state(first) == "__Captures_resolvedFunction0(count, limit)")
    }

    @Test("an empty transition relation exports FALSE and retains deadlock checking")
    func rendersEmptyNext() throws {
        let compilation = try TLASpec(name: "Stuck", variables: [.init(name: "count", initial: .int(0))],
            actions: [], invariants: []).compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let module = try program.renderModule()
        #expect(module.renderedModuleSource.contains("Next == FALSE\n"))
        #expect(module.configuration.checkDeadlock)
        let formal = try compilation.render()
        #expect(formal.tlaBundle.tla.contains("Next == FALSE\n"))
        #expect(formal.checksDeadlock)
    }

    @Test("unsupported typed module closures fail explicitly without a source-rendering fallback")
    func rejectsUnsupportedClosure() throws {
        let compilation = try TLASpec(name: "UnsupportedClosure",
            variables: [.init(name: "count", initial: .int(0))], formalParameters: [.init("Base")],
            actions: [], invariants: []).compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        do {
            _ = try program.renderModule()
            Issue.record("Export accepted an unresolved module closure")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unsupportedGeneratedValueShape)
            #expect(diagnostic.path == "export.UnsupportedClosure")
        }
        var native = NativeSwiftEmitter(model: try MacroCompilation(typeName: "UnsupportedClosure", program: program))
        let members = try native.machineMembers().map(\.description).joined(separator: "\n")
        #expect(members.contains("public static func render()"))
        #expect(members.contains("Resolve the complete module closure before typed export."))
        #expect(!members.contains(".compile("))
    }

    @Test("native and TLA generation consume the same resolved call and binders")
    func rendersResolvedProgram() throws {
        let increment = FormalOperatorDefinition(name: "Increment", parameters: [.value("input", typeName: "Int")],
            body: .add(.variable("input"), .int(1)))
        let spec = TLASpec(name: "ResolvedCalls", variables: [.init(name: "count", initial: .int(0))],
            actions: [.init(name: "advance", body: .assign(.named("count"),
                .operatorApplication(.reference("Increment", arity: 1), [.value(.variable("count"))])))],
            invariants: [], formalOperatorDefinitions: [increment])
        let compilation = try spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let renderer = CompiledTLARenderer(moduleName: "ResolvedCalls", reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions)
        let function = try #require(program.functions.first)
        let parameter = try renderer.binderName(#require(function.parameters.first?.binder))
        #expect(try renderer.resolvedFunctionDefinitions() == [
            "RECURSIVE __ResolvedCalls_resolvedFunction0(_)",
            "__ResolvedCalls_resolvedFunction0(\(parameter)) == (\(parameter) + 1)"
        ])
        #expect(try renderer.action(#require(program.behavior.actions.first).body) == "count' = __ResolvedCalls_resolvedFunction0(count)")
        let module = try program.renderModule()
        #expect(module.renderedModuleSource.contains("advance == count' = __ResolvedCalls_resolvedFunction0(count)"))
        #expect(module.renderedModuleSource.contains("__ResolvedCalls_resolvedFunction0(\(parameter)) == (\(parameter) + 1)"))
        #expect(!module.renderedModuleSource.contains("Increment("))
        var native = NativeSwiftEmitter(model: try MacroCompilation(typeName: "ResolvedCalls", program: program))
        let members = try native.machineMembers().map(\.description).joined(separator: "\n")
        #expect(members.contains("public static func render()"))
        #expect(!members.contains(".compile("))
    }

    @Test("recursive calls remain references and function domain guards remain explicit")
    func preservesRecursiveCallsAndGuards() throws {
        let compilation = try TLASpec(name: "RecursiveCalls", variables: [
            .init(name: "__RecursiveCalls_resolvedFunction0", initial: .int(0))
        ], actions: [], invariants: []).compile()
        let binder = BinderID(ordinal: 0)
        let argument = CompiledExpression(operation: .boundValue(binder), resultType: .int, children: [])
        let zero = CompiledExpression(operation: .value(.integer(0)), resultType: .int, children: [])
        let recursive = CompiledExpression(operation: .call(.init(ordinal: 0)), resultType: .int, children: [argument])
        let domain = CompiledExpression(operation: .greaterOrEqual, resultType: .bool, children: [argument, zero])
        let renderer = CompiledTLARenderer(moduleName: "RecursiveCalls",
            reservedNames: ["__RecursiveCalls_resolvedFunction0_"], layout: compilation.layout,
            bindings: .init(binders: [binder: "input"]), operators: .init(), actions: [],
            functions: [.init(parameters: [(binder, .int)], resultType: .int, body: recursive, domainGuard: domain)])
        #expect(try renderer.resolvedFunctionDefinitions() == [
            "RECURSIVE __RecursiveCalls_resolvedFunction0__(_)",
            "__RecursiveCalls_resolvedFunction0__(input) == CASE (input >= 0) -> (__RecursiveCalls_resolvedFunction0__(input))"
        ])
        #expect(throws: CompilationDiagnostic.self) {
            try renderer.state(.init(operation: .call(.init(ordinal: 0)), resultType: .int, children: []))
        }
        #expect(throws: CompilationDiagnostic.self) {
            try renderer.state(.init(operation: .call(.init(ordinal: 99)), resultType: .int, children: [zero]))
        }
    }
}
