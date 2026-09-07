import Testing
@testable import SwiftTLA
import SwiftParser
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
                        Do(Step.advance) { Assign(value, to: Value.second(Right.right)) }
                    })
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let model = try TLASpecVerifier.parseAndVerify(declaration)
        var emitter = try NativeSwiftEmitter(model: model)
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        let projected = try emitter.expression(.tupleAccess(.tupleLiteral([.value(.constant("right")), .divide(.value(.integer(1)), .value(.integer(0)))]), 1), expected: .finite([.constant("left"), .constant("right")]))
        #expect(projected.contains("NativeValue0.member_right_1"))
        #expect(projected.contains("_NativeMachineOperations.divide"))
        #expect(projected.hasSuffix(".first"))
        #expect(emitter.finiteValues == [[.constant("left"), .constant("right")]])
        #expect(generated.contains("public let value: NativeValue0"))
        #expect(generated.contains("enum NativeValue0: Hashable, Sendable"))
        #expect(!generated.contains("case member_outside"))
        #expect(!generated.contains("public let value: _Atom"))
        #expect(!Parser.parse(source: "struct Expansion {\n\(generated)\n}").hasError)
    }

}
