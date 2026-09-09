import Testing
import SwiftSyntax
import SwiftParser
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct NestedFunctionBindings {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case left, right
        static var defaultValue: Self { .left }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }
    enum Step: String, CaseIterable { case stop }
    static var spec: TLASpec {
        #spec("NestedFunctionBindings") {
            Algorithm("NestedFunctionBindings", scoped: { scope in
                let matrix = scope.sharedVar("matrix", initial: Function<Node, Function<Node, Int>>.mapping { outer in
                    Function<Node, Int>.mapping { inner in
                        If(outer == inner, then: 1, else: 0)
                    }
                })
                Do(Step.stop) { Assign(matrix, to: matrix); Stop() }
            })
        }
    }
}

@Suite("Lexical expression bindings retain outer references")
struct LexicalExpressionBindingTests {
    private func expression(_ source: String) throws -> ExprSyntax {
        try #require(Parser.parse(source: source).statements.first?.item.as(ExprSyntax.self))
    }

    @Test("Nested mapping produces the identity matrix in builder, parser and native execution")
    func nestedMapping() throws {
        typealias Node = NestedFunctionBindings.Node
        let builder = Function<Node, Function<Node, Int>>.mapping { outer in
            Function<Node, Int>.mapping { inner in
                If(outer == inner, then: 1, else: 0)
            }
        }
        let expected: [Node: [Node: Int]] = [.left: [.left: 1, .right: 0], .right: [.left: 0, .right: 1]]
        let formal = try evaluateClosed(builder.raw)
        let compilation = try NestedFunctionBindings.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let matrix = try #require(compilation.layout.testVariableID(named: "matrix"))
        #expect(try initial.value(for: matrix) == CompiledValue(formal: formal))
        let machine = try NestedFunctionBindings.makeMachine()
        #expect(machine.state.matrix == expected)
        for row in Node.allCases {
            for column in Node.allCases {
                #expect(try evaluateClosed(.functionApply(.functionApply(.value(formal), .value(row.tlaValue)), .value(column.tlaValue))) == .int(expected[row]![column]!))
            }
        }
    }

    @Test("#spec preserves nested set and sequence binder locations")
    func macroPreservesCollectionBindings() throws {
        let specification = #spec("NestedCollectionBindings") {
            Algorithm("NestedCollectionBindings") { scope in
                let filtered = scope.sharedVar("filtered", initial: Where(SetExpr<Int>.literal(1, 2)) { outer in
                    Where(SetExpr<Int>.literal(1, 2)) { inner in outer == inner }.cardinality == 1
                })
                let mapped = scope.sharedVar("mapped", initial: SetExpr<Int>.literal(1, 2).mapping { outer in
                    SetExpr<Int>.literal(10, 20).mapping { inner in outer.expr + inner.expr }
                })
                let selected = scope.sharedVar("selected", initial: TupleExpr<Int>.literal(1, 2).selecting { outer in
                    TupleExpr<Int>.literal(1, 2).selecting(where: { inner in outer == inner }).count == 1
                })
                Do(NestedFunctionBindings.Step.stop) {
                    Assign(filtered, to: filtered)
                    Assign(mapped, to: mapped)
                    Assign(selected, to: selected)
                    Stop()
                }
            }
        }
        let compilation = try specification.compile()
        let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let expected: [(String, CompiledValue)] = [
            ("filtered", .set([.integer(1), .integer(2)])),
            ("mapped", .set([.set([.integer(11), .integer(21)]), .set([.integer(12), .integer(22)])])),
            ("selected", .tuple([.integer(1), .integer(2)]))
        ]
        for (name, value) in expected {
            let variable = try #require(compilation.layout.testVariableID(named: name))
            #expect(try initial.value(for: variable) == value)
        }
    }

    @Test("#spec leaves non-closure formal mapping calls unchanged")
    func macroPreservesExpressionMappingOverload() throws {
        let specification = #spec("ExpressionMapping") {
            Algorithm("ExpressionMapping") { scope in
                let values = scope.sharedVar("values", initial: Expr<SetExpr<Int>>(
                    StateExpr.setLiteral([.int(1), .int(2)]).mapping(.int(9))
                ))
                Do(NestedFunctionBindings.Step.stop) { Assign(values, to: values); Stop() }
            }
        }
        let compilation = try specification.compile()
        let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let values = try #require(compilation.layout.testVariableID(named: "values"))
        #expect(try initial.value(for: values) == .set([.integer(9)]))
    }

    @Test("Nested filters preserve outer values in parsed and builder predicates")
    func nestedFilters() throws {
        let builder = Where(SetExpr<Int>.literal(1, 2)) { outer in
            Where(SetExpr<Int>.literal(1, 2)) { inner in
                outer == inner
            }.cardinality == 1
        }
        let parsed = try #require(SpecParser.decodeStateExpr(expression("""
        Where(SetExpr<Int>.literal(1, 2)) { outer in
            Where(SetExpr<Int>.literal(1, 2)) { inner in outer == inner }.cardinality == 1
        }
        """)))
        #expect(try evaluateClosed(builder.raw) == .set([.int(1), .int(2)]))
        #expect(try evaluateClosed(parsed) == evaluateClosed(builder.raw))
    }

    @Test("Nested set mapping retains the outer member in each image")
    func nestedSetMapping() throws {
        let builder = SetExpr<Int>.literal(1, 2).mapping { outer in
            SetExpr<Int>.literal(10, 20).mapping { inner in outer.expr + inner.expr }
        }
        let parsed = try #require(SpecParser.decodeStateExpr(expression("""
        SetExpr<Int>.literal(1, 2).mapping { outer in
            SetExpr<Int>.literal(10, 20).mapping { inner in outer.expr + inner.expr }
        }
        """)))
        let expected = TLAValue.set([.set([.int(11), .int(21)]), .set([.int(12), .int(22)])])
        #expect(try evaluateClosed(builder.raw) == expected)
        #expect(try evaluateClosed(parsed) == expected)
    }

    @Test("Nested set filtering retains independent predicate members")
    func nestedSetFiltering() throws {
        let builder = SetExpr<Int>.literal(1, 2).filtering { outer in
            SetExpr<Int>.literal(1, 2).filtering { inner in outer == inner }.cardinality == 1
        }
        let parsed = try #require(SpecParser.decodeStateExpr(expression("""
        SetExpr<Int>.literal(1, 2).filtering { outer in
            SetExpr<Int>.literal(1, 2).filtering { inner in outer == inner }.cardinality == 1
        }
        """)))
        #expect(try evaluateClosed(builder.raw) == .set([.int(1), .int(2)]))
        #expect(try evaluateClosed(parsed) == .set([.int(1), .int(2)]))
    }

    @Test("Nested folds retain the outer element and accumulator")
    func nestedFolds() throws {
        let builder = Fold(TupleExpr<Int>.literal(1, 2), startingWith: 0) { outer, accumulated in
            Fold(TupleExpr<Int>.literal(10), startingWith: accumulated) { inner, partial in
                inner + partial + outer
            }
        }
        let parsed = try #require(SpecParser.decodeStateExpr(expression("""
        Fold(TupleExpr<Int>.literal(1, 2), startingWith: 0) { outer, accumulated in
            Fold(TupleExpr<Int>.literal(10), startingWith: accumulated) { inner, partial in
                inner + partial + outer
            }
        }
        """)))
        #expect(try evaluateClosed(builder.raw) == .int(23))
        #expect(try evaluateClosed(parsed) == .int(23))
    }

    @Test("Nested formal universal closures retain independent members")
    func nestedFormalUniversals() throws {
        let builder = StateExpr.forAll(.set([1, 2])) { outer in
            StateExpr.forAll(.set([1, 2])) { inner in StateExpr.equal(outer, inner) }
        }
        #expect(try evaluateClosed(builder) == .bool(false))
    }

    @Test("Nested collection predicates retain distinct member references")
    func nestedCollectionPredicates() throws {
        let parsed = try #require(SpecParser.decodeStateExpr(expression("""
        devices.allSatisfy { outer in devices.contains { inner in outer == inner } }
        """)))
        guard case .forAll(_, let outer, .exists(_, let inner, .equal(let lhs, let rhs))) = parsed else {
            Issue.record("Expected nested collection quantifiers")
            return
        }
        #expect(outer != inner)
        #expect(lhs == .functionApply(.variable("devices"), .variable(outer)))
        #expect(rhs == .functionApply(.variable("devices"), .variable(inner)))
    }
}
