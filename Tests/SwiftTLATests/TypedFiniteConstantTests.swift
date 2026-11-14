@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
import SwiftTLAMacros
import Testing

private func parseClosure(_ source: String) throws -> ClosureExprSyntax {
    try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
}

@TLAModel
private struct TypedFiniteConstantGeneratedModel {
    static var spec: TLASpec {
        #spec("TypedFiniteConstantGeneratedModel") {
            Constant("Value", SetExpr<Int>(1, 2))
            Constant("WF_Probe", SetExpr<Int>(3, 4))
            let count = Var<Int>("count")
            Variable(count, 0)
        }
    }
}

@TLAModel
private struct NestedFiniteConstantGeneratedModel {
    enum Value: String, FiniteTLAValueDomain {
        case v1, v2
        static var defaultValue: Self { .v1 }
        static let finiteValues: [Self] = [.v1, .v2]
    }

    enum Acceptor: String, FiniteTLAValueDomain {
        case a1, a2, a3
        static var defaultValue: Self { .a1 }
        static let finiteValues: [Self] = [.a1, .a2, .a3]
    }

    static var spec: TLASpec {
        #spec("NestedFiniteConstantGeneratedModel") {
            Constant("Value", SetExpr<Value>(Value.v1, .v2))
            Constant("Acceptor", SetExpr<Acceptor>(.a1, Acceptor.a2, .a3))
            Constant("Quorum", SetExpr<SetExpr<Acceptor>>(
                SetExpr<Acceptor>(.a1, Acceptor.a2),
                SetExpr<Acceptor>(.a2, .a3)
            ))
            let count = Var<Int>("count")
            Variable(count, 0)
        }
    }
}

struct TypedFiniteConstantTests {
    @Test(arguments: ["Value", "WF_Value", "SF_Value", "_1", "TRUE", "FALSE", "BOOLEAN", "STRING", "Len", "Int", "Nat",
                      "_", "Init", "Next", "Spec", "vars", "Cardinality", "IsFiniteSet"])
    func builderRetainsAndExportsAClosedTypedFiniteSet(_ name: String) throws {
        let sibling = ["WF_Value": "_WF_Value", "SF_Value": "_SF_Value", "_1": "v_1"][name] ?? "Sibling"
        let spec = TLASpec("TypedFiniteConstant") {
            Constant(name, SetExpr<Int>(1, 2))
            Constant(sibling, SetExpr<Int>(3))
            let count = Var<Int>("count")
            Variable(count, Expr<Int>(.cardinality(.variable(name))))
        }
        #expect(spec.constants == [ConstantDecl(name, .set([.int(1), .int(2)])),
                                    ConstantDecl(sibling, .set([.int(3)]))])
        let compilation = try spec.compile()
        let count = try #require(compilation.layout.testVariableID(named: "count"))
        let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        #expect(try initial.value(for: count) == .integer(2))
        let bundle = try compilation.render().tlaBundle
        let binding = try #require(bundle.cfg.split(separator: "\n").first {
            $0.hasPrefix("CONSTANT ") && $0.hasSuffix(" = {1, 2}")
        })
        let formalName = String(binding.dropFirst("CONSTANT ".count).prefix { !$0.isWhitespace })
        #expect(formalName.utf8.contains { (65...90).contains($0) || (97...122).contains($0) })
        #expect(!formalName.hasPrefix("WF_") && !formalName.hasPrefix("SF_"))
        #expect(!["TRUE", "FALSE", "BOOLEAN", "STRING", "Len", "Int", "Nat"].contains(formalName))
        #expect(formalName != sibling)
        #expect(name == "Value" ? formalName == name : formalName != name)
        let declaration = try #require(bundle.tla.split(separator: "\n").first { $0.hasPrefix("CONSTANTS ") })
        let names = declaration.dropFirst("CONSTANTS ".count).split(separator: ",").map { String($0.filter { !$0.isWhitespace }) }
        #expect(names.count == 2 && names.contains(formalName) && names.contains(sibling))
        #expect(bundle.tla.contains("ASSUME \(formalName) = {1, 2}"))
        #expect(bundle.cfg.contains("CONSTANT \(sibling) = {3}"))
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let module = try program.renderModule()
        #expect(module.configuration.declarations.contains("CONSTANT \(formalName) = {1, 2}"))
        #expect(module.renderedModuleSource.contains("ASSUME \(formalName) = {1, 2}"))
    }

    @Test func parserRetainsTheSameTypedFiniteSet() throws {
        let closure = try parseClosure("""
        {
            Constant("Value", SetExpr<Int>(1, 2))
            let count = Var<Int>("count")
            Variable(count, 0)
        }
        """)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsed.constants == [ConstantDecl("Value", .set([.int(1), .int(2)]))])
    }

    @Test func macroExpansionRetainsTheTypedFiniteSet() throws {
        #expect(TypedFiniteConstantGeneratedModel.spec.constants == [
            ConstantDecl("Value", .set([.int(1), .int(2)])),
            ConstantDecl("WF_Probe", .set([.int(3), .int(4)]))
        ])
        let bundle = try TypedFiniteConstantGeneratedModel.render().tlaBundle
        #expect(bundle.tla.contains("ASSUME Value = {1, 2}"))
        let binding = try #require(bundle.cfg.split(separator: "\n").first { $0.hasSuffix(" = {3, 4}") })
        let formalName = String(binding.dropFirst("CONSTANT ".count).prefix { !$0.isWhitespace })
        #expect(!formalName.hasPrefix("WF_"))
        #expect(bundle.tla.contains("ASSUME \(formalName) = {3, 4}"))
    }

    @Test func macroExpansionRetainsNestedFiniteEnumConstants() throws {
        #expect(NestedFiniteConstantGeneratedModel.spec.constants == [
            ConstantDecl("Value", .set([.string("v1"), .string("v2")])),
            ConstantDecl("Acceptor", .set([.string("a1"), .string("a2"), .string("a3")])),
            ConstantDecl("Quorum", .set([
                .set([.string("a1"), .string("a2")]),
                .set([.string("a2"), .string("a3")])
            ]))
        ])
        #expect(try NestedFiniteConstantGeneratedModel.spec.compile().render().tlaBundle.tla.contains("ASSUME Value = {\"v1\", \"v2\"}"))
        #expect(try NestedFiniteConstantGeneratedModel.spec.compile().render().tlaBundle.tla.contains("ASSUME Quorum = {{\"a1\", \"a2\"}, {\"a2\", \"a3\"}}"))
    }

    @Test func parserRejectsUnconsumedConstantSyntax() throws {
        let declarations = [
            #"Constant("Bad", 1, 2)"#,
            #"Constant(name: "Bad", 1)"#,
            #"Constant("Bad", value: 1)"#,
            #"Constant("Bad", 1) { 2 }"#,
            #"Constant("Bad", 1) { 2 } otherwise: { 3 }"#,
            #"Constant("Bad")"#
        ]
        for declaration in declarations {
            let closure = try parseClosure("{ Constant(\"Kept\", 7); \(declaration) }")
            let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)
            #expect(parsed.constants == [ConstantDecl("Kept", .int(7))])
            #expect(parsed.diagnostics.count == 1, "\(declaration): \(parsed.diagnostics)")
            #expect(parsed.diagnostics.first?.expected == "Constant(\"Name\", value)")
        }
    }

    @Test func parserDiagnosesDynamicConstantValues() throws {
        let closure = try parseClosure("""
        {
            let values = Var<SetExpr<Int>>("values")
            Variable(values, SetExpr<Int>())
            Constant("Value", values)
        }
        """)
        let parsed = SpecParser.parseSpecClosure(named: "Parsed", closure)

        guard let diagnostic = parsed.diagnostics.first else {
            Issue.record("Expected a dynamic constant diagnostic")
            return
        }
        #expect(diagnostic.message == "Constant 'Value' must be static; dynamic formal expressions are not constant values.")
        #expect(diagnostic.expected == "a literal value or SetExpr<Element>(...) with static members")
    }
}
