import Foundation
import Testing
@testable import SwiftTLA
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import SwiftBasicFormat
@testable import SwiftTLAPlugin

struct NativeCodeGenerationTests {
    @Test("Record construction preserves field names across execution and rendering")
    func recordFieldNames() throws {
        let record = StateRecordExpression([
            .init(name: "z", value: .variable("count")),
            .init(name: "a", value: .int(2))
        ])
        let specification = TLASpec(name: "RecordIdentity", variables: [
            .init(name: "count", initial: .int(0))
        ], actions: [], invariants: [
            .init(name: "Equal", body: .equal(.recordLiteral(record), .recordLiteral(record))),
            .init(name: "Read", body: .equal(.recordAccess(.recordLiteral(record), "z"), .int(0)))
        ])
        let compilation = try specification.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let predicate = try #require(program.behavior.invariants.first).predicate.expression
        let constructor = try #require(predicate.children.first)
        guard case .recordLiteral(let fields) = constructor.operation else {
            Issue.record("Expected resolved record construction")
            return
        }
        #expect(fields == ["a", "z"])
        #expect(constructor.children.map(\.resultType) == [.int, .int])
        let syntax = try constructor.operation.tlaSyntax(operandCount: constructor.children.count,
            binderName: { _ in "unused" })
        #expect(syntax == [.text("["), .text("a |-> "), .operand(0), .text(", "),
            .text("z |-> "), .operand(1), .text("]")])
        var values: [CompiledValue] = [.integer(2), .integer(0)]
        try constructor.operation.apply(to: &values, operandCount: 2)
        #expect(values == [.record(CompiledRecord([
            .init(key: .string("a"), value: .integer(2)),
            .init(key: .string("z"), value: .integer(0))
        ]))])
        let read = try #require(program.behavior.invariants.first { $0.name == "Read" })
        let access = try #require(read.predicate.expression.children.first)
        #expect(access.operation == .recordAccess(try #require(fields.last)))
        #expect(access.resultType == .int)
        try access.operation.apply(to: &values, operandCount: 1)
        #expect(values == [.integer(0)])
    }

    @Test("Fixed record updates omit unused storage while retaining operand evaluation")
    func fixedRecordUpdatesAvoidUnusedBindings() throws {
        let specification = TLASpec(name: "RecordUpdate", variables: [
            .init(name: "record", initial: .record(TLARecord([.init("count", .int(0))])))
        ], actions: [
            .init(name: "advance", body: .assign(.named("record"), .except(
                .variable("record"), .value(.string("count")), .int(1))))
        ], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let model = try MacroCompilation(typeName: "RecordUpdate", program: program)
        var emitter = NativeSwiftEmitter(model: model)
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(!generated.contains("let _updatedKey"))
        #expect(!generated.contains("let _originalValue"))
        #expect(generated.contains("_ = state.state.record"))
        #expect(generated.contains("let _replacementValue"))
        #expect(!Parser.parse(source: "struct Expansion {\n\(generated)\n}").hasError)
    }

    @Test("Resolved checked views retain their formal constraint and failure behavior")
    func resolvedViewsPreserveConstraints() throws {
        let specification = TLASpec(name: "CheckedView", variables: [], actions: [], invariants: [
            .init(name: "Valid", body: .equal(.assertView(.int(1), .integer), .int(1)))
        ])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let predicate = try #require(program.behavior.invariants.first).predicate.expression
        let view = try #require(predicate.children.first)
        #expect(view.operation == .assertView(.integer))
        #expect(view.resultType == .int)
        var values: [CompiledValue] = [.boolean(false), .integer(1)]
        try view.operation.apply(to: &values, operandCount: 1)
        #expect(values == [.boolean(false), .integer(1)])
        var invalid: [CompiledValue] = [.string("one")]
        #expect(throws: EvalError.noMatchingCase) {
            try view.operation.apply(to: &invalid, operandCount: 1)
        }
    }

    @Test("Implicit representation changes are explicit typed conversion nodes")
    func resolvesExplicitConversions() throws {
        let specification = TLASpec(name: "Conversions", variables: [
            .init(name: "number", initialization: .value(.int(1)), generatedSwiftType: "Number", origin: .source)
        ], actions: [], invariants: [
            .init(name: "Small", body: .lessThan(.variable("number"), .int(2)))
        ])
        let types = SourceTypeResolver(metadata: .init(enums: [.init(typeName: "Number", cases: [(name: "one", value: .int(1))])]))
        let program = try CompiledProgram(inputs: types.resolve(in: specification.compile()))
        let predicate = try #require(program.behavior.invariants.first).predicate.expression
        let conversion = try #require(predicate.children.first)
        #expect(conversion.operation == .convert)
        #expect(conversion.resultType == .int)
        let source = try #require(conversion.children.first)
        #expect(source.resultType == .named("Number"))
        #expect(program.canProject(source: source.resultType, to: conversion.resultType))
        var formalValues: [CompiledValue] = [.integer(1)]
        try conversion.operation.apply(to: &formalValues, operandCount: 1)
        #expect(formalValues == [.integer(1)])
    }

    @Test("Local declaration scopes resolve directly to their typed executable body")
    func resolvesLocalDeclarationScopes() throws {
        let specification = TLASpec(name: "LocalScopes", variables: [], actions: [], invariants: [
            .init(name: "Valid", body: .letIn([], .letIn([
                LocalOperator("Valid", body: .value(.bool(true)))
            ], .recursiveCall("Valid", []))))
        ])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let predicate = try #require(program.behavior.invariants.first).predicate.expression
        guard case .call = predicate.operation else {
            Issue.record("Expected the resolved call without enclosing declaration scopes")
            return
        }
        #expect(predicate.resultType == .bool)
        #expect(program.functions.count == 1)
        let function = try #require(program.functions.first)
        #expect(function.body.operation == .value(.boolean(true)))
        let runtime = CompiledRuntime(program: program)
        let initial = try #require(try runtime.initialStates().first)
        #expect(try runtime.invariantHolds(try #require(program.behavior.invariants.first), in: initial))
    }

    @Test("Resolved calls execute during initialization")
    func initializesThroughResolvedCalls() throws {
        let source = TLASpec(name: "InitialCall", variables: [
            .init(name: "value", initialization: .expression(.letIn([
                LocalOperator("Seed", body: .int(3))
            ], .recursiveCall("Seed", []))), origin: .source)
        ], actions: [], invariants: [])
        let compilation = try source.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let states = try CompiledRuntime(program: program).initialStates()
        #expect(try states == CompiledRuntime(compilation: compilation).initialStates())
        #expect(try #require(states.first).value(for: .init(ordinal: 0)) == .integer(3))
    }

    @Test("Forwarded callbacks retain captured values across resolved calls")
    func forwardsResolvedCallbacks() throws {
        let callback = FormalOperator.lambda(.init(parameters: ["item"],
            body: .add(.variable("item"), .variable("offset"))))
        let source = TLASpec(name: "ForwardedCallback", variables: [], actions: [], invariants: [
            .init(name: "Result", body: .letValue("offset", .int(7), .equal(
                .operatorApplication(.reference("Forward", arity: 2), [
                    .operator(callback), .value(.int(2))
                ]), .int(9))))
        ], formalOperatorDefinitions: [
            .init(name: "Apply", parameters: [.operator("operation", arity: 1), .value("value")],
                body: .operatorApplication(.reference("operation", arity: 1), [.value(.variable("value"))])),
            .init(name: "Forward", parameters: [.operator("operation", arity: 1), .value("value")],
                body: .operatorApplication(.reference("Apply", arity: 2), [
                    .operator(.reference("operation", arity: 1)), .value(.variable("value"))
                ]))
        ])
        let compilation = try source.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let runtime = CompiledRuntime(program: program)
        let initial = try #require(try runtime.initialStates().first)
        #expect(try runtime.invariantHolds(try #require(program.behavior.invariants.first), in: initial))
    }

    @Test("Resolved actions share choice, binding, and simultaneous-update enumeration")
    func enumeratesResolvedActions() throws {
        let specification = TLASpec(name: "ResolvedActions", variables: [
            .init(name: "first", initial: .int(0)), .init(name: "second", initial: .int(1))
        ], actions: [.init(name: "choose", body:
            .or(
                .existsAction("choice", .value(.set([.int(2), .int(3)])),
                    .define("selected", .variable("choice"),
                        .ifElse(.value(.bool(true)),
                            .and(.assign(.named("first"), .variable("second")),
                                 .assign(.named("second"), .variable("selected"))),
                            .unchanged(.named("first"))))),
                .and(.guard_(.value(.bool(false))),
                     .assign(.named("first"), .divide(.value(.int(1)), .value(.int(0)))))))
        ], invariants: [])
        let compilation = try specification.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let resolved = try CompiledRuntime(program: program).successors(from: initial)
        let formal = try runtime.successors(from: initial)
        #expect(resolved.count == 2)
        #expect(resolved.map(\.state) == formal.map(\.state))
        #expect(resolved.map(\.arguments) == formal.map(\.arguments))
        #expect(resolved.map(\.action) == formal.map(\.action))
        let first = try #require(program.layout.variables.first?.id)
        let second = try #require(program.layout.variables.last?.id)
        #expect(try resolved.map { try $0.state.value(for: first) } == [.integer(1), .integer(1)])
        #expect(try resolved.map { try $0.state.value(for: second) } == [.integer(2), .integer(3)])
    }

    @Test("Native emission plans execution functions without planning temporal-only functions")
    func plansReachableFunctions() throws {
        let count = Var<Int>("count", 0)
        let specification = TLASpec("FunctionPlanning") {
            Variable(count)
            FormalDefinition("Increment", parameters: [.value("value")],
                body: StateExpr.tupleAccess(.tupleLiteral([.variable("value"), .value(.int(1))]), 1) + 1)
            FormalDefinition("Positive", parameters: [.value("value")],
                body: StateExpr.tupleAccess(.tupleLiteral([.variable("value"), .value(.string("formal-only"))]), 1) > 0)
            Action("advance") { count.becomes(FormalCall("Increment", count)) }
            Always("PositiveCount", FormalCall("Positive", count))
        }
        let compilation = try specification.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        #expect(program.functions.count == 2)
        let property = try #require(program.behavior.temporalProperties.first)
        guard case .always(let predicate) = property.expression,
              case .call(let temporalFunction) = predicate.expression.operation else {
            Issue.record("Expected a resolved temporal function call")
            return
        }
        let model = try MacroCompilation(typeName: "FunctionPlanning",
            program: program)
        var emitter = NativeSwiftEmitter(model: model)
        #expect(emitter.functionPlans.isEmpty)
        #expect(emitter.typeDeclarations.records == [.tuple([.int, .int])])
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(emitter.functionPlans.count == 1)
        #expect(!generated.contains("NativeRecord1"))
        #expect(emitter.functionPlans[temporalFunction] == nil)
        #expect(!generated.contains("func _operator\(temporalFunction.ordinal)("))
        #expect(!Parser.parse(source: "struct Expansion {\n\(generated)\n}").hasError)
    }

    @Test("Predicate dependencies retain transitive enabledness through resolution")
    func predicateEnablednessDependencies() throws {
        let specification = TLASpec(name: "InvariantDependencies", variables: [
            .init(name: "count", initial: .int(0))
        ], actions: [
            .init(name: "ready", body: .and(
                .guard_(.lessThan(.variable("count"), .value(.int(1)))), .unchanged(.named("count")))),
            .init(name: "advance", body: .and(
                .guard_(.enabledAction("ready")), .assign(.named("count"), .value(.int(1)))))
        ], invariants: [.init(name: "CanAdvance", body: .enabledAction("advance"))],
            temporalProperties: [.init(name: "AlwaysCanAdvance", expr: .always(.enabledAction("advance")))],
            constraint: .or(.equal(.variable("count"), .value(.int(0))), .not(.enabledAction("ready"))))
        let compilation = try specification.compile()
        let ready = try #require(compilation.layout.testActionID(named: "ready"))
        let advance = try #require(compilation.layout.testActionID(named: "advance"))
        let invariant = try #require(compilation.semantics.behavior.invariants.first)
        #expect(invariant.predicate.enabledActions == [ready, advance])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let resolved = try #require(program.behavior.invariants.first)
        #expect(resolved.id == invariant.id)
        #expect(resolved.name == "CanAdvance")
        #expect(resolved.predicate.enabledActions == invariant.predicate.enabledActions)
        #expect(resolved.predicate.expression.resultType == .bool)
        #expect(compilation.semantics.behavior.constraint?.enabledActions == [ready])
        #expect(program.behavior.constraint?.enabledActions == [ready])
        let model = try MacroCompilation(typeName: "InvariantDependencies", program: program)
        var emitter = NativeSwiftEmitter(model: model)
        #expect(emitter.enabledActionIDs == [ready, advance])
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(generated.contains("func _enabledActions"))
        for action in [ready, advance] {
            #expect(generated.contains("required.contains(\(action.ordinal))"))
            #expect(generated.contains("func _updates\(action.ordinal)("))
        }
        #expect(!Parser.parse(source: "struct Expansion {\n\(generated)\n}").hasError)
        let temporal = try #require(program.behavior.temporalProperties.first)
        guard case .always(let predicate) = temporal.expression else {
            Issue.record("Expected an always predicate")
            return
        }
        #expect(predicate.enabledActions == [ready, advance])
        #expect(predicate.expression.resultType == .bool)
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(runtime.initialStates().first)
        #expect(try runtime.invariantHolds(invariant, in: initial))
        let successor = try #require(runtime.successors(for: advance, from: initial).first)
        #expect(try !runtime.invariantHolds(invariant, in: successor.state))
    }

    @Test("Enum emission uses resolved formal order rather than declaration order")
    func resolvedEnumOrdering() throws {
        let compilation = try TLASpec(name: "EnumOrdering", variables: [], actions: [], invariants: []).compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver(metadata: .init(enums: [
            .init(typeName: "Priority", cases: [(name: "high", value: .int(10)), (name: "low", value: .int(1))])
        ])).resolve(in: compilation))
        let model = try MacroCompilation(typeName: "EnumOrdering",
            program: program)
        let emitter = NativeSwiftEmitter(model: model)
        #expect(program.enums.cases["Priority"]?.map(\.name) == ["low", "high"])
        #expect(program.enums.domains["Priority"] == [.integer(1), .integer(10)])
        #expect(try emitter.literal(.integer(10), as: .named("Priority")) == "Priority.`high`")
        let ordering = try emitter.ordering(.named("Priority"))
        #expect(ordering.contains("case .`low`: return 0"))
        #expect(ordering.contains("case .`high`: return 1"))
    }

    @Test("Native model values use their declared identity in Swift and formal export")
    func readableModelValueEmission() throws {
        let specification = TLASpec(name: "ModelValues", variables: [
            .init(name: "selected", initialization: .value(.constant("nodeA")), origin: .compiler)
        ], actions: [], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "ModelValues", program: program))
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(generated.contains("enum _ModelValue"))
        #expect(generated.contains("case nodeA = \"nodeA\""))
        #expect(try emitter.literal(.constant("nodeA"), as: .modelValue) == "_ModelValue.nodeA")
        #expect(generated.contains("TLAValue.constant("))
    }

    @Test("Model value declarations include nested literals and referenced domains before emission")
    func modelValuesAreResolved() {
        let declarations = NativeTypeDeclarations(
            types: [.modelValue, .named("Choice"), .finite([.constant("finite")])],
            literals: [
                .function([.constant("key"): .tuple([.constant("nested")])]),
                .set([.constant("nested"), .constant("set")]),
                .record(.init([.init(key: .string("field"), value: .constant("record"))]))
            ],
            namedDomains: ["Choice": [.constant("named")], "Unused": [.constant("unused")]]
        )
        #expect(declarations.modelValueCases.keys.sorted() == ["finite", "key", "named", "nested", "record", "set"])
        #expect(declarations.modelValueCases["nested"] == "nested")
        #expect(declarations.modelValueCases["unused"] == nil)
    }

    @Test("Generated type declarations include nested fields once before emission")
    func nestedTypeDeclarations() {
        let finite = CompiledValueType.finite([.integer(1), .string("missing")])
        let record = CompiledValueType.record([.init(name: "value", type: .set(finite))])
        let union = CompiledValueType.union([.int, record])
        let declarations = NativeTypeDeclarations(types: [union, record, union], literals: [], namedDomains: [:])
        #expect(declarations.records == [record])
        #expect(declarations.unions == [[.int, record]])
        #expect(declarations.finiteValues == [[.integer(1), .string("missing")]])
        #expect(declarations.names.count == 3)
    }

    @Test("Shared predicates emit one local function per checked expression")
    func sharedPredicateDeclarations() throws {
        let compilation = try TLASpec(name: "SharedPredicates", variables: [], actions: [], invariants: []).compile()
        let leaf = CompiledExpression(operation: .value(.boolean(true)),
            resultType: .bool, children: [])
        let root = CompiledExpression(operation: .and,
            resultType: .bool, children: [leaf, leaf])
        let behavior = CompiledBehavior(
            checkDeadlock: compilation.semantics.behavior.checkDeadlock,
            initializations: [], actions: [], enabledActionIndices: [], enabledActionDependencies: [:],
            invariants: [], temporalProperties: [], fairness: compilation.semantics.behavior.fairness,
            constraint: nil, assume: nil)
        let program = CompiledProgram(identity: compilation.identity, layout: compilation.layout,
            behavior: behavior, enums: .init(), projections: [], variableTypes: [:], bindingTypes: [:],
            functions: [])
        let model = try MacroCompilation(typeName: "SharedPredicates",
            program: program)
        var emitter = NativeSwiftEmitter(model: model)
        let source = try emitter.booleanExpression(root, state: "state.", substitutions: [:], activeFunctions: [])
        #expect(source.components(separatedBy: "func _predicate0()").count == 2)
        #expect(source.contains("let left = try _predicate0()"))
        #expect(source.contains("return try _predicate0()"))
        #expect(!Parser.parse(source: source).hasError)
    }

    @Test("Resolved call targets retain each specialization's types")
    func resolvedCallTypes() throws {
        let specification = TLASpec("CallTypes") {
            let number = Var<Int>("number")
            let flag = Var<Bool>("flag")
            Variable(number, 0)
            Variable(flag, false)
            FormalDefinition("Identity", parameters: [.value("value")], body: StateExpr.variable("value"))
            SwiftTLA.Action("update") {
                number.becomes(FormalCall("Identity", 1))
                flag.becomes(FormalCall("Identity", true))
            }
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        var calls: [CompiledExpression] = []
        for action in program.behavior.actions {
            _ = action.map { expression in
                if case .call = expression.operation { calls.append(expression) }
                return expression
            }
        }
        #expect(calls.count == 2)
        #expect(Set(calls.map(\.resultType)) == [.int, .bool])
        for expression in calls {
            guard case .call(let target) = expression.operation else {
                Issue.record("A named operator must resolve to a function")
                continue
            }
            let function = program[target]
            #expect(function.parameters.map(\.type) == expression.children.map(\.resultType))
            #expect(function.resultType == expression.resultType)
        }
    }

    @Test("Models without actions omit unreachable dispatch methods")
    func actionlessModelsOmitDispatch() throws {
        let specification = TLASpec("StateOnly") {
            Variable(Var<Int>("count"), 0)
        }
        let compilation = try specification.compile()
        let model = try MacroCompilation(typeName: "StateOnly",
            program: CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation)))
        var emitter = NativeSwiftEmitter(model: model)
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(generated.contains("func enabledActions()"))
        #expect(!generated.contains("func isEnabled("))
        #expect(generated.contains("func successors()"))
        #expect(!generated.contains("func successors(for:"))
        #expect(!generated.contains("func send("))
        #expect(!generated.contains("switch action"))
    }

    @Test("Generated execution uses typed Swift without formal runtime machinery")
    func emittedMachineExecutesSwift() throws {
        let source = Parser.parse(source: """
        struct NativeCounter {
            enum Step: String, CaseIterable { case advance }
            static var spec: TLASpec {
                #spec("NativeCounter") {
                    Algorithm("NativeCounter", scoped: { scope in
                        let count = scope.sharedVar("count", initial: 0)
                        While(Step.advance, true) {
                            When(count < 3)
                            Assign(count, to: count + 1)
                        }
                    })
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let generated = members.map(\.description).joined(separator: "\n")
        for forbidden in ["Self.spec", ".compile()", "CompiledRuntime", "CompiledEvaluator",
                          "CompiledState", "CompiledValue", "Decoder", "_GeneratedMachineStorage"] {
            #expect(!generated.contains(forbidden), "Execution unexpectedly references \(forbidden)")
        }
        let execution = members.filter {
            $0.as(FunctionDeclSyntax.self)?.name.text != "formalProjection"
        }.map(\.description).joined(separator: "\n")
        #expect(!execution.contains("TLAValue"))
        #expect(!execution.contains("formalProjection("))
        #expect(generated.contains("_NativeMachineOperations.add"))
        #expect(generated.contains("switch action"))
        #expect(generated.contains("guard"))
        #expect(!generated.contains("func _enabledActions"))
        let terminal = try #require(model.program.layout.actions.first {
            $0.declaration.name == CompilerControlSymbol.terminatingAction.rawValue
        })
        #expect(generated.contains("func isTerminated()"))
        #expect(generated.contains("func _updates\(terminal.id.ordinal)("))
        #expect(!Parser.parse(source: "struct Expansion {\n\(generated)\n}").hasError)
        print("native-code-generation model=counter declarations=\(members.count) sourceBytes=\(generated.utf8.count)")
    }
    @Test("Finite union state exposes only its admitted native enum cases")
    func finiteUnionUsesDedicatedNativeType() throws {
        let source = Parser.parse(source: """
        struct NativeUnion {
            enum Left: String, TLAValueType {
                case left
                var tlaValue: TLAValue { .constant(rawValue) }
            }
            enum Right: String, TLAValueType {
                case right
                var tlaValue: TLAValue { .constant(rawValue) }
            }
            enum Foreign: String, TLAValueType {
                case outside
                var tlaValue: TLAValue { .constant(rawValue) }
            }
            typealias Value = OneOf<Left, Right>
            enum Step: String, CaseIterable { case advance }
            static var spec: TLASpec {
                #spec("NativeUnion") {
                    Algorithm("NativeUnion", scoped: { scope in
                        let value = scope.sharedVar("value", initial: Value.first(Left.left))
                        Do(Step.advance) { Assign(value, to: Value.second(Pair<Right, Int>.literal(Expr<Right>(Right.right), Expr<Int>(1) / 0).first())) }
                    })
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = NativeSwiftEmitter(model: model)
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(generated.contains("NativeValue0.member_right_1"))
        #expect(generated.contains("_NativeMachineOperations.divide"))
        #expect(NativeTypeDeclarations(program: model.program).finiteValues == [[.constant("left"), .constant("right")]])
        #expect(generated.contains("public let value: NativeValue0"))
        #expect(generated.contains("enum NativeValue0: Hashable, Sendable"))
        #expect(!generated.contains("case member_outside"))
        #expect(!generated.contains("public let value: _ModelValue"))
        #expect(!Parser.parse(source: "struct Expansion {\n\(generated)\n}").hasError)
    }

}

extension NativeCodeGenerationTests {
    @Test("Nested predicates emit Swift that remains valid after macro formatting")
    func nestedPredicateEmission() throws {
        let leaf = StateExpr.forAll(.set(["ready"]), "member", .equal(.variable("count"), .int(0)))
        let predicate = (0..<8).reduce(leaf) { expression, _ in .and(leaf, expression) }
        let compilation = try TLASpec(
            name: "NestedPredicates",
            variables: [
                .init(name: "count", initialization: .value(.int(0)), origin: .compiler),
                .init(name: "result", initialization: .value(.bool(false)), origin: .compiler)
            ],
            actions: [.init(name: "evaluate", body: .assign(.named("result"), predicate))],
            invariants: []
        ).compile()
        let model = try MacroCompilation(
            typeName: "NestedPredicates",
            program: try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        )
        var emitter = NativeSwiftEmitter(model: model)
        let declarations = try emitter.machineMembers()
        for source in [declarations.map(\.description), declarations.map { $0.formatted().description }] {
            let syntax = Parser.parse(source: "struct Expansion {\n\(source.joined(separator: "\n"))\n}")
            #expect(!syntax.hasError, "\(ParseDiagnosticsGenerator.diagnostics(for: syntax).map(\.message))")
        }
    }

    @Test("Nested source updates preserve scoped variables through parentheses")
    func nestedSourceUpdates() throws {
        let update = (0..<12).reduce("count.expr") { expression, _ in "(\(expression) + 1)" }
        let source = Parser.parse(source: """
        struct NestedSource {
            enum Step: String, CaseIterable { case advance }
            static var spec: TLASpec {
                #spec("NestedSource") {
                    Algorithm("NestedSource", scoped: { scope in
                        let count = scope.sharedVar("count", initial: 0)
                        Do(Step.advance) { Assign(count, to: \(update)) }
                    })
                }
            }
        }
        """)
        #expect(!source.hasError)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        let sourceSpec = try #require(try TLASpecVerifier.findSpec(in: declaration.memberBlock.members))
        let enums = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
        let compilation = try SpecParser.parseSpecClosure(
            named: sourceSpec.name, sourceSpec.closure, sourceTypes: .init(enums: enums)).compile()
        #expect(model.program.identity == compilation.identity)
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "advance"))
        let count = try #require(compilation.layout.testVariableID(named: "count"))
        let successor = try #require(try runtime.successors(for: action, from: initial).first)
        #expect(try successor.state.value(for: count) == .integer(12))
    }

    @Test("Nested state-dependent updates emit valid Swift")
    func nestedUpdateEmission() throws {
        let update = (0..<12).reduce(StateExpr.variable("count")) { expression, _ in
            .add(expression, .int(1))
        }
        let compilation = try TLASpec(
            name: "NestedUpdate",
            variables: [.init(name: "count", initialization: .value(.int(0)), origin: .compiler)],
            actions: [.init(name: "advance", body: .assign(.named("count"), update))],
            invariants: []
        ).compile()
        let model = try MacroCompilation(
            typeName: "NestedUpdate",
            program: try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        )
        var emitter = NativeSwiftEmitter(model: model)
        let members = try emitter.machineMembers()
        let generated = members.map(\.description).joined(separator: "\n")
        let syntax = Parser.parse(source: "struct Expansion {\n\(generated)\n}")
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntax).map(\.message)
        #expect(!syntax.hasError, "\(diagnostics)")
    }
}

extension NativeCodeGenerationTests {
    @Test("KVsnap type checking handles nested collection operators on a test worker")
    func kvsnapTypeChecking() throws {
        let sourceURL = packageRoot().appendingPathComponent("Sources/UpstreamParity/CanonicalCorpus/KVsnap.swift")
        let source = Parser.parse(source: try String(contentsOf: sourceURL, encoding: .utf8))
        let declaration = try #require(source.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first)
        _ = try TLASpecVerifier.parseAndVerify(declaration)
    }
}
