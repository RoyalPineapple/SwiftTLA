import Foundation
import Testing
@testable import SwiftTLA
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
import SwiftBasicFormat
@testable import SwiftTLAPlugin

struct NativeCodeGenerationTests {
    @Test("Shared predicates emit one local function per checked expression")
    func sharedPredicateDeclarations() throws {
        let compilation = try TLASpec(name: "SharedPredicates", variables: [], actions: [], invariants: []).compile()
        let leaf = NativeCheckedExpression(expression: .value(.boolean(true)), operatorParameters: [],
            resultType: .bool, computationType: .bool, call: nil, children: [])
        let root = NativeCheckedExpression(expression: .and(leaf.expression, leaf.expression), operatorParameters: [],
            resultType: .bool, computationType: .bool, call: nil, children: [leaf, leaf])
        let program = NativeResolvedProgram(projections: [], variableTypes: [:], bindingTypes: [:],
            expressions: [leaf, root], calls: [:], functions: [], callbacks: [], initializations: [:],
            actions: [:], invariants: [:], constraint: nil, assume: nil)
        let model = MacroCompilation(typeName: "SharedPredicates", compilation: compilation, enumInfos: [],
            surface: try MachineSurfacePlan(layout: compilation.layout, semantics: compilation.semantics),
            nativeProgram: program)
        var emitter = NativeSwiftEmitter(model: model)
        let source = try emitter.booleanExpression(root, state: "state.", substitutions: [:], activeFunctions: [])
        #expect(source.components(separatedBy: "func _predicate0()").count == 2)
        #expect(source.contains("let left = try _predicate0()"))
        #expect(source.contains("return try _predicate0()"))
        #expect(!Parser.parse(source: source).hasError)
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
        let members = try MacroExpander.generateStateMachineMembers(model: model)
        let generated = members.map(\.description).joined(separator: "\n")
        for forbidden in ["Self.spec", ".compile()", "CompiledRuntime", "CompiledEvaluator",
                          "CompiledState", "CompiledValue", "TLAValue", "Decoder", "_GeneratedMachineStorage"] {
            #expect(!generated.contains(forbidden), "Execution unexpectedly references \(forbidden)")
        }
        #expect(generated.contains("_NativeMachineOperations.add"))
        #expect(generated.contains("switch action"))
        #expect(generated.contains("guard"))
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
        #expect(emitter.finiteValues == [[.constant("left"), .constant("right")]])
        #expect(generated.contains("public let value: NativeValue0"))
        #expect(generated.contains("enum NativeValue0: Hashable, Sendable"))
        #expect(!generated.contains("case member_outside"))
        #expect(!generated.contains("public let value: _Atom"))
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
        let model = MacroCompilation(
            typeName: "NestedPredicates", compilation: compilation, enumInfos: [],
            surface: try MachineSurfacePlan(layout: compilation.layout, semantics: compilation.semantics),
            nativeProgram: try NativeResolvedProgram(compilation: compilation)
        )
        let declarations = try MacroExpander.generateStateMachineMembers(model: model)
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
        let runtime = CompiledRuntime(compilation: model.compilation)
        let initial = try #require(try runtime.initialStates().first)
        let action = try #require(model.compilation.layout.testActionID(named: "advance"))
        let count = try #require(model.compilation.layout.testVariableID(named: "count"))
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
        let model = MacroCompilation(
            typeName: "NestedUpdate", compilation: compilation, enumInfos: [],
            surface: try MachineSurfacePlan(layout: compilation.layout, semantics: compilation.semantics),
            nativeProgram: try NativeResolvedProgram(compilation: compilation)
        )
        let members = try MacroExpander.generateStateMachineMembers(model: model)
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
