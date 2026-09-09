import Testing
@testable import SwiftTLA

@Suite struct NativeResolutionContractTests {
    @Test("checked reads retain stored representations alongside their contextual types")
    func storedReadRepresentations() throws {
        let specification = TLASpec(name: "StoredRepresentations", variables: [
            .init(name: "node", initialization: .value(.int(1)), generatedSwiftType: "Node", origin: .compiler),
            .init(name: "nodes", initialization: .value(.function([.int(0): .int(1)])), generatedSwiftType: "[Int: Node]", origin: .compiler)
        ], actions: [], invariants: [])
        let plan = NativeMachinePlan(compilation: try specification.compile())
        let checker = try NativeTypeInference(plan: plan, sourceTypes: .init(enums: ["Node": [.int(1), .int(2)]]))
        let node = try #require(plan.variables.first { $0.declaration.name == "node" })
        let nodes = try #require(plan.variables.first { $0.declaration.name == "nodes" })
        for expression in [
            CompiledStateExpr.stateVariable(node.id),
            .functionApply(.stateVariable(nodes.id), .value(.integer(0)))
        ] {
            let checked = try checker.resolutionScope(expression, expected: .int)
            #expect(checked.resultType == .int)
            #expect(checked.computationType == .named("Node"))
        }
    }

    @Test("unrelated declared types do not expand the program's conversion table")
    func conversionsFollowExpressionUses() throws {
        let names = (0..<12).map { "Value\($0)" }
        let metadata = NativeSourceTypeMetadata(enums: Dictionary(uniqueKeysWithValues: names.map { ($0, [TLAValue.int(0)]) }))
        let variables = names.enumerated().map { index, name in
            NamedVar(name: "value\(index)", initialization: .value(.int(0)), generatedSwiftType: name, origin: .compiler)
        }
        let specification = TLASpec(name: "RequiredConversions", variables: variables + [
            .init(name: "result", initialization: .value(.int(0)), generatedSwiftType: "Int", origin: .compiler)
        ], actions: [
            .init(name: "read", body: .assign(.named("result"), .variable("value0")))
        ], invariants: [])
        let program = try NativeResolvedProgram(plan: .init(compilation: specification.compile()), sourceTypes: metadata)
        #expect(program.projections == [.init(source: .named("Value0"), target: .int)])
    }

    @Test("the resolved graph freezes independent typed uses of one formal body")
    func polymorphicUsesHaveSeparateBodies() throws {
        let identity = FormalOperatorDefinition(name: "Identity", parameters: [.value("value")], body: .variable("value"))
        let plan = NativeMachinePlan(compilation: try TLASpec(name: "ResolvedCalls", variables: [
            .init(name: "number", initialization: .expression(.int(0)), origin: .compiler),
            .init(name: "text", initialization: .value(.string("")), origin: .compiler)
        ], actions: [.init(name: "step", body: .and(
            .assign(.named("number"), .operatorApplication(.reference("Identity", arity: 1), [.value(.int(1))])),
            .assign(.named("text"), .operatorApplication(.reference("Identity", arity: 1), [.value(.value(.string("one")))]))
        ))], invariants: [], formalOperatorDefinitions: [identity]).compile())
        let program = try NativeResolvedProgram(plan: plan)
        #expect(program.functions.count == 2)
        #expect(Set(program.functions.map(\.resultType)) == [.int, .string])
        for function in program.functions {
            #expect(program[function.body].resultType == function.resultType)
            #expect(function.parameterTypes == [function.resultType])
        }
        #expect(program.expressions.allSatisfy { $0.resultType.resolved && $0.computationType.resolved })
        for expression in program.expressions {
            #expect(expression.children.allSatisfy { program.expressions.indices.contains($0.ordinal) })
            if let call = expression.call {
                switch call.target {
                case .function(let id): #expect(program.functions.indices.contains(id.ordinal))
                case .callback(let id): #expect(program.callbacks.indices.contains(id.ordinal))
                }
            }
        }
    }

    @Test("recursive calls reference a finite registered function graph")
    func recursiveBodiesUseBackReferences() throws {
        let operation = FormalOperatorDefinition(name: "CountDown", parameters: [.value("value")], body: .ifThenElse(
            .lessOrEqual(.variable("value"), .int(0)), .int(0),
            .operatorApplication(.reference("CountDown", arity: 1), [.value(.subtract(.variable("value"), .int(1)))])
        ))
        let program = try NativeResolvedProgram(plan: plan(operation: operation, arguments: [.value(.int(2))], boolean: false))
        #expect(program.functions.count <= 2)
        #expect(program.expressions.contains { expression in
            guard let call = expression.call, case .function(let id) = call.target else { return false }
            return program[id].resultType == .int
        })
    }

    @Test("native resolution diagnoses recursively growing specialization shapes")
    func growingArgumentShapesAreRejected() throws {
        let operation = FormalOperatorDefinition(name: "Nest", parameters: [.value("n"), .value("value")], body: .ifThenElse(
            .equal(.variable("n"), .int(0)), .bool(true),
            .operatorApplication(.reference("Nest", arity: 2), [
                .value(.subtract(.variable("n"), .int(1))), .value(.tupleLiteral([.variable("value")]))
            ])
        ))
        let plan = try plan(operation: operation, arguments: [.value(.int(1)), .value(.int(0))], boolean: true)
        #expect(throws: CompilationDiagnostic.self) { try NativeResolvedProgram(plan: plan) }
    }

    @Test("native resolution diagnoses recursive growth inside a stable record shape")
    func growingRecordFieldsAreRejected() throws {
        let operation = FormalOperatorDefinition(name: "NestRecord", parameters: [.value("n"), .value("value")], body: .ifThenElse(
            .equal(.variable("n"), .int(0)), .bool(true),
            .operatorApplication(.reference("NestRecord", arity: 2), [
                .value(.subtract(.variable("n"), .int(1))),
                .value(.recordLiteral(.init(["field": .tupleLiteral([.recordAccess(.variable("value"), "field")])])))
            ])
        ))
        let plan = try plan(operation: operation, arguments: [
            .value(.int(1)), .value(.recordLiteral(.init(["field": .int(0)])))
        ], boolean: true)
        #expect(throws: CompilationDiagnostic.self) { try NativeResolvedProgram(plan: plan) }
    }

    @Test("sequence selection resolves function-backed input and Boolean predicate into an array")
    func selectedSequenceAnnotations() throws {
        let sequence = StateExpr.functionLiteral(.integerRange(.int(1), .int(3)), "index", .variable("index"))
        let selection = StateExpr.sequenceSelect(sequence, "item", .greaterThan(.variable("item"), .int(1)))
        let plan = NativeMachinePlan(compilation: try TLASpec(name: "SelectedSequence", variables: [
            .init(name: "items", initialization: .expression(selection), generatedSwiftType: "[Int]", origin: .compiler)
        ], actions: [], invariants: []).compile())
        let program = try NativeResolvedProgram(plan: plan)
        let root = try #require(program.initializations.values.first)
        let node = program[root]
        #expect(node.resultType == .array(.int))
        #expect(program[node.children[0]].resultType == .dictionary(.int, .int))
        #expect(program[node.children[1]].resultType == .bool)
    }

    private func plan(operation: FormalOperatorDefinition, arguments: [FormalCallArgument], boolean: Bool) throws -> NativeMachinePlan {
        let call = StateExpr.operatorApplication(.reference(operation.name, arity: arguments.count), arguments)
        return .init(compilation: try TLASpec(name: "ResolvedRecursion", variables: [
            .init(name: "number", initialization: .expression(.int(0)), origin: .compiler)
        ], actions: [], invariants: [.init(name: "Check", body: boolean ? call : .equal(call, .int(0)))],
            formalOperatorDefinitions: [operation]).compile())
    }
}
