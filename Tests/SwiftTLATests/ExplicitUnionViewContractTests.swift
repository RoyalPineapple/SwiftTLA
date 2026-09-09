import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin
@testable import SwiftTLA

@Suite("Explicit union views preserve and check formal shape evidence")
struct ExplicitUnionViewContractTests {
    @Test("A view preserves valid values and rejects the wrong alternative")
    func checkedViews() throws {
        let scalar = Expr<OneOf<Int, SetExpr<Int>>>(.value(.int(7)))
        #expect(try compiledValue(scalar.assumingFirst(Int.self).raw) == .int(7))
        #expect(throws: EvalError.noMatchingCase) {
            _ = try compiledValue(scalar.assumingSecond(SetExpr<Int>.self).raw)
        }
        let set = Expr<OneOf<Int, SetExpr<Int>>>(.value(.set([.int(7)])))
        #expect(try compiledValue(set.assumingSecond(SetExpr<Int>.self).raw) == .set([.int(7)]))
        #expect(throws: EvalError.noMatchingCase) {
            _ = try compiledValue(set.assumingFirst(Int.self).raw)
        }
    }


    @Test("View checks preserve operand errors and lazy conditional branches")
    func checkedViewEvaluationOrder() throws {
        #expect(throws: EvalError.divisionByZero) {
            _ = try compiledValue(.assertView(.divide(.value(.int(1)), .value(.int(0))), .string))
        }
        #expect(try compiledValue(.ifThenElse(
            .value(.bool(true)), .value(.int(3)), .assertView(.value(.int(1)), .string)
        )) == .int(3))
    }

    @Test("Structural views validate every member and sequence domain")
    func structuralMembership() throws {
        let invalid: [(FormalValueShape, TLAValue)] = [
            (.set(.integer), .set([.int(1), .string("wrong")])),
            (.sequence(.integer), .function([.int(2): .int(1)])),
            (.sequence(.integer), .function([.int(1): .int(1)])),
            (.tuple([.integer, .boolean]), .tuple([.int(1)])),
            (.record([.init(name: "count", shape: .integer)]), .record(["count": .string("wrong")])),
            (.function(key: .integer, value: .boolean), .function([.int(1): .int(0)]))
        ]
        for (shape, value) in invalid {
            #expect(throws: EvalError.noMatchingCase) {
                _ = try compiledValue(.assertView(.value(value), shape))
            }
        }
        #expect(try compiledValue(.assertView(.value(.tuple([.int(3)])), .sequence(.integer)))
            == .tuple([.int(3)]))
    }

    @Test("Source metatypes use authoritative alias and enum evidence")
    func sourceViews() throws {
        let members: [TLAValue] = [.int(1), .int(2)]
        let parser = ParserSession(sourceTypes: .init(
            aliases: ["Members": "SetExpr<Node>"], enums: ["Node": members], finiteViewDomains: ["Node": members]
        ))
        let source = "temporary.assumingSecond(Members.self)"
        let expression = try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
        #expect(parser.decodeTypedFacadeValue(expression, scope: .empty)
            == .assertView(.variable("temporary"), .set(.finite(typeName: "Node", values: members))))
    }


    @Test("Enum views require the declared finite witness and preserve its exact domain")
    func sourceEnumViewAuthority() throws {
        let source = """
        struct Model {
            enum Ordinary: String, TLAValueType {
                case one, two
                static var defaultValue: Self { .one }
            }
            enum `repeat`: String, FiniteTLAValueDomain {
                case value
                static var defaultValue: Self { .value }
                static let finiteValues: [Self] = [.value]
            }
            enum Bounded: Int, FiniteTLAValueDomain {
                case one = 1, two = 2, three = 3
                static var defaultValue: Self { .two }
                static let finiteValues: [Self] = [.two, .one]
            }
        }
        """
        let declaration = try #require(Parser.parse(source: source).statements.first?.item.as(StructDeclSyntax.self))
        let enums = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
        let metadata = try TLASpecVerifier.sourceTypes(in: declaration.memberBlock.members, enums: enums)
        #expect(metadata.enums["Ordinary"] == [.string("one"), .string("two")])
        #expect(metadata.finiteViewDomains["Ordinary"] == nil)
        #expect(metadata.finiteViewDomains["Bounded"] == [.int(2), .int(1)])
        #expect(metadata.enums["`repeat`"] == [.string("value")])
        #expect(try metadata.formalShape(for: "`repeat`") == .finite(typeName: "repeat", values: [.string("value")]))
        #expect(try metadata.formalShape(for: "Bounded") == .finite(typeName: "Bounded", values: [.int(2), .int(1)]))
        let parser = ParserSession(sourceTypes: metadata)
        let expression = try #require(Parser.parse(source: "value.assumingFirst(Ordinary.self)").statements.first?.item.as(ExprSyntax.self))
        #expect(parser.decodeTypedFacadeValue(expression, scope: .empty) == nil)
    }

    @Test("Unsupported witnesses fail compilation instead of erasing the view")
    func unsupportedWitnesses() {
        let shapes: [FormalValueShape] = [
            .unsupported("custom view"), .union(.set(.integer), .sequence(.integer)),
            .record([.init(name: "count", shape: .integer), .init(name: "count", shape: .integer)])
        ]
        for shape in shapes {
            #expect(throws: CompilationDiagnostic.self) {
                _ = try compiledValue(.assertView(.value(.int(1)), shape))
            }
        }
    }

    @Test("Rendered union predicates test scalar alternatives before structural alternatives")
    func unionPredicateOrdering() {
        let shape = FormalValueShape.union(.set(.integer), .finite(typeName: "Empty", values: [.string("none")]))
        let predicate = shape.predicate(for: "value")
        #expect(predicate.hasPrefix("((value \\in {\"none\"})"))
        #expect(predicate.contains("\\A"))
        #expect(!predicate.contains("SUBSET"))
    }

    @Test("Integer view predicates import their standard module only when needed")
    func viewModuleDependencies() throws {
        for shape in [FormalValueShape.set(.integer), .set(.boolean)] {
            let value = StateExpr.value(.set([]))
            let specification = TLASpec(name: "ViewModules", variables: [], actions: [],
                invariants: [.init(name: "View", body: .equal(.assertView(value, shape), value))],
                extendsModules: [])
            let rendered = try specification.compile().renderedTLAModuleBundle().root.tla
            let imports = try #require(rendered.split(separator: "\n").first { $0.hasPrefix("EXTENDS ") })
            #expect(imports.contains("Integers") == (shape == .set(.integer)))
        }
    }
}
