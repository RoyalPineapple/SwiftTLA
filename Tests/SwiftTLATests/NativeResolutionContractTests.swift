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
            if case .functionApply = expression {
                #expect(checked.operandTypes == [.dictionary(.int, .named("Node")), .int])
            }
        }
    }

    @Test("bound nominal reads preserve storage while projecting to scalar results")
    func boundReadRepresentations() throws {
        let plan = NativeMachinePlan(compilation: try TLASpec(name: "BoundRead", variables: [
            .init(name: "node", initialization: .value(.int(1)), generatedSwiftType: "Node", origin: .compiler)
        ], actions: [], invariants: []).compile())
        let checker = try NativeTypeInference(plan: plan, sourceTypes: .init(enums: ["Node": [.int(1), .int(2)]]))
        let variable = try #require(plan.variables.first)
        let binder = BinderID(ordinal: 0)
        let binding = CompiledStateExpr.letValue(binder, .stateVariable(variable.id), .boundValue(binder))
        let scope = try checker.resolutionScope(binding, expected: .int).scope
        let checked = try scope.resolutionScope(.boundValue(binder), expected: .int)
        #expect(checked.resultType == .int)
        #expect(checked.computationType == .named("Node"))
        #expect(checked.scope.bindings[binder] == .named("Node"))
    }

    @Test("linked binding domains refine without recursive source checking")
    func linkedBindingDomains() throws {
        let plan = NativeMachinePlan(compilation: try TLASpec(
            name: "LinkedDomains", variables: [], actions: [], invariants: []
        ).compile())
        let checker = try NativeTypeInference(plan: plan, sourceTypes: .init(enums: ["Node": [.int(1), .int(2)]]))
        let count = 1_000
        var expression = CompiledStateExpr.boundValue(.init(ordinal: count - 1))
        for index in (0..<count).reversed() {
            let source: CompiledStateExpr = index == 0
                ? .value(.integer(1)) : .boundValue(.init(ordinal: index - 1))
            expression = .letValue(.init(ordinal: index), source, expression)
        }
        let checked = try checker.resolutionScope(expression, expected: .named("Node"))
        #expect(checked.resultType == .named("Node"))
        #expect(checked.scope.bindings[BinderID(ordinal: 0)] == .named("Node"))
        #expect(checked.scope.bindings[BinderID(ordinal: count - 1)] == .named("Node"))
    }

    @Test("function constructors retain the selected representation within a union")
    func functionConstructorUnionContext() throws {
        let plan = NativeMachinePlan(compilation: try TLASpec(
            name: "FunctionUnion", variables: [], actions: [], invariants: []
        ).compile())
        let checker = try NativeTypeInference(plan: plan)
        let function = CompiledStateExpr.functionLiteral(
            .setLiteral([.value(.integer(1))]), .init(ordinal: 0), .value(.integer(2))
        )
        let expected = NativeType.union([.dictionary(.int, .int), .bool])
        let checked = try checker.resolutionScope(function, expected: expected)
        #expect(checked.resultType == expected)
        #expect(checked.computationType == .dictionary(.int, .int))
        #expect(checked.operandTypes == [.set(.int), .int])
    }

    @Test("predicate operands retain nominal context in the resolved graph")
    func predicateOperandRepresentations() throws {
        let member = StateExpr.variable("member")
        let members = StateExpr.variable("members")
        let specification = TLASpec(name: "PredicateOperands", variables: [
            .init(name: "member", initialization: .value(.int(1)), generatedSwiftType: "Member", origin: .compiler),
            .init(name: "members", initialization: .value(.set([.int(1)])), generatedSwiftType: "Set<Member>", origin: .compiler)
        ], actions: [], invariants: [
            .init(name: "Equal", body: .equal(.int(1), member)),
            .init(name: "NotEqual", body: .notEqual(member, .int(2))),
            .init(name: "Subset", body: .subset(.setLiteral([]), members)),
            .init(name: "Membership", body: .in(.int(1), members))
        ])
        let plan = NativeMachinePlan(compilation: try specification.compile())
        let program = try NativeResolvedProgram(plan: plan, sourceTypes: .init(enums: ["Member": [.int(1), .int(2)]]))
        for invariant in plan.invariants {
            let root = try #require(program.invariants[invariant.id])
            let node = program[root]
            let operands = node.children.map { program[$0].resultType }
            #expect(node.resultType == .bool)
            switch node.expression {
            case .equal, .notEqual:
                #expect(operands == [.named("Member"), .named("Member")])
            case .subset:
                #expect(operands == [.set(.named("Member")), .set(.named("Member"))])
            case .in:
                #expect(operands == [.named("Member"), .set(.named("Member"))])
            default:
                Issue.record("Expected a comparison or membership predicate")
            }
        }
    }

    @Test("sequence operations retain integer-keyed function operands")
    func sequenceSourceRepresentations() throws {
        let sequence = StateExpr.functionLiteral(.integerRange(.int(1), .int(3)), "index", .variable("index"))
        let operations: [(name: String, expression: StateExpr, type: NativeType)] = [
            ("head", .tupleHead(sequence), .int),
            ("length", .tupleLength(sequence), .int),
            ("access", .tupleDynamicAccess(sequence, .int(2)), .int),
            ("tail", .tupleTail(sequence), .array(.int)),
            ("remove", .tupleRemoving(sequence, .int(2)), .array(.int)),
            ("append", .tupleAppend(sequence, .int(4)), .array(.int)),
            ("concatenate", .tupleConcatenate(sequence, sequence), .array(.int))
        ]
        for operation in operations {
            let plan = NativeMachinePlan(compilation: try TLASpec(name: "SequenceOperands", variables: [
                .init(name: operation.name, initialization: .expression(operation.expression),
                      generatedSwiftType: operation.type.swiftType, origin: .compiler)
            ], actions: [], invariants: []).compile())
            let program = try NativeResolvedProgram(plan: plan)
            let root = try #require(program.initializations.values.first)
            let node = program[root]
            let source = try #require(node.children.first)
            #expect(node.resultType == operation.type)
            #expect(program[source].resultType == .dictionary(.int, .int))
        }
    }

    @Test("fold retains array and integer-keyed function operands")
    func foldOperandRepresentations() throws {
        let sources: [(StateExpr, NativeType)] = [
            (.tupleLiteral([.int(1), .int(2)]), .array(.int)),
            (.functionLiteral(.integerRange(.int(1), .int(2)), "index", .variable("index")), .dictionary(.int, .int))
        ]
        for (source, sourceType) in sources {
            let fold = StateExpr.foldFunction(
                FormalLambda(parameters: ["element", "accumulator"],
                    body: .add(.variable("element"), .variable("accumulator"))),
                initial: .int(0), sequence: source
            )
            let plan = NativeMachinePlan(compilation: try TLASpec(name: "FoldOperands", variables: [
                .init(name: "total", initialization: .expression(fold), generatedSwiftType: "Int", origin: .compiler)
            ], actions: [], invariants: []).compile())
            let program = try NativeResolvedProgram(plan: plan)
            let root = try #require(program.initializations.values.first)
            let node = program[root]
            #expect(node.resultType == .int)
            #expect(node.children.map { program[$0].resultType } == [.int, .int, sourceType])
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

    @Test("unused enclosing arguments do not duplicate local function specializations")
    func localFunctionsCaptureOnlyReferencedValues() throws {
        let operation = FormalOperatorDefinition(name: "Outer", parameters: [.value("value"), .value("unused")], body: .letIn([
            .init("Read", parameters: [], body: .variable("value")),
            .init("Forward", parameters: [], body: .recursiveCall("Read", []))
        ], .recursiveCall("Forward", [])))
        let first = StateExpr.operatorApplication(.reference("Outer", arity: 2), [.value(.int(1)), .value(.bool(true))])
        let second = StateExpr.operatorApplication(.reference("Outer", arity: 2), [.value(.int(2)), .value(.value(.string("unused")))])
        let plan = NativeMachinePlan(compilation: try TLASpec(name: "LocalCaptures", variables: [], actions: [],
            invariants: [.init(name: "Comparison", body: .lessThan(first, second))],
            formalOperatorDefinitions: [operation]).compile())
        let outer = try #require(plan.formalOperatorDefinitions.first)
        guard case .letIn(let definitions, _) = outer.body,
              case .value(let value) = outer.parameters[0] else {
            Issue.record("Expected local definitions inside a value-parameterized operator")
            return
        }
        #expect(definitions[0].capturedBindings == [value])
        #expect(definitions[1].capturedBindings.isEmpty)
        #expect(definitions[1].referencedOperators == [definitions[0].id])
        let program = try NativeResolvedProgram(plan: plan)
        let locals = program.functions.filter { $0.parameters.isEmpty }
        #expect(locals.count == 2)
        #expect(locals.allSatisfy { $0.resultType == .int })
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
