import Testing
@testable import SwiftTLA
import SwiftParser
import SwiftParserDiagnostics
import SwiftSyntax
@testable import SwiftTLAPlugin

struct NativeCodeGenerationTests {
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
            nativeProgram: try NativeResolvedProgram(plan: .init(compilation: compilation))
        )
        let members = try MacroExpander.generateStateMachineMembers(model: model)
        let generated = members.map(\.description).joined(separator: "\n")
        let syntax = Parser.parse(source: "struct Expansion {\n\(generated)\n}")
        let diagnostics = ParseDiagnosticsGenerator.diagnostics(for: syntax).map(\.message)
        #expect(!syntax.hasError, "\(diagnostics)")
    }
}
