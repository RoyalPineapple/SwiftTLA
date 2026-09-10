@testable import SwiftTLAPlugin
import Testing
@testable import SwiftTLA

@Suite("Compound operands retain declared element domains")
struct NativeCompoundContextTests {
    private var metadata: NativeSourceTypeMetadata {
        .init(records: ["ColorRecord": [.init(sourceName: "color", name: "color", swiftType: "Color")]],
              enums: ["Color": [.string("red"), .string("blue")]])
    }

    @Test("nested comparisons preserve their resolved Boolean result")
    func nestedComparisons() throws {
        let compilation = try TLASpec(name: "NestedComparisons", variables: [
            .init(name: "number", initialization: .value(.int(0)), origin: .compiler)
        ], actions: [], invariants: []).compile()
        let inference = try NativeTypeInference(compilation: compilation)
        let expression = (0..<12).reduce(CompiledStateExpr.value(.boolean(true))) { nested, _ in
            .equal(nested, .value(.boolean(true)))
        }
        #expect(try inference.type(of: expression) == .bool)
        #expect(throws: CompilationDiagnostic.self) {
            try inference.type(of: .equal(expression, .value(.integer(1))))
        }
    }

    @Test("Equality and inequality acquire nominal evidence at every compound field")
    func comparisonContext() throws {
        let fixtures: [(String, TLAValue, NativeType)] = [
            ("SetExpr<Color>", .set([.string("red")]), .set(.named("Color"))),
            ("TupleExpr<Color>", .tuple([.string("red")]), .array(.named("Color"))),
            ("Pair<Int, Color>", .tuple([.int(1), .string("red")]), .tuple([.int, .named("Color")])),
            ("Function<Int, Color>", .function([.int(1): .string("red")]), .dictionary(.int, .named("Color"))),
            ("Record<ColorRecord>", .record(["color": .string("red")]), .record([.init(name: "color", type: .named("Color"))]))
        ]
        for (hint, value, expected) in fixtures {
            for reversed in [false, true] {
                let stored = StateExpr.variable("stored")
                let literal = StateExpr.value(value)
                let lhs = reversed ? literal : stored
                let rhs = reversed ? stored : literal
                let compilation = try TLASpec(
                    name: "CompoundContext",
                    variables: [.init(name: "stored", initialization: .value(value), generatedSwiftType: hint, origin: .compiler)],
                    actions: [], invariants: [], constraint: .and(.equal(lhs, rhs), .notEqual(lhs, rhs))
                ).compile()

                let evidence = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
                #expect(evidence.variables[compilation.layout.variables[0].id] == expected)
            }
        }
    }

    @Test("Literal-left set operations retain the stored set's enum representation")
    func setOperationContext() throws {
        let literal = StateExpr.setLiteral([.value(.string("red"))])
        let stored = StateExpr.variable("stored")
        let operations: [StateExpr] = [.union(literal, stored), .intersection(literal, stored), .setDifference(literal, stored)]
        for operation in operations {
            let compilation = try TLASpec(
                name: "SetOperationContext",
                variables: [.init(name: "stored", initialization: .value(.set([.string("red")])), generatedSwiftType: "SetExpr<Color>", origin: .compiler)],
                actions: [], invariants: [], constraint: .and(.subset(literal, stored), .equal(operation, stored))
            ).compile()

            let evidence = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
            #expect(evidence.variables[compilation.layout.variables[0].id] == .set(.named("Color")))
        }
    }

    @Test("Contextual compound literals cannot introduce undeclared enum members")
    func invalidLiteralRemainsRejected() throws {
        let compilation = try TLASpec(
            name: "InvalidCompoundContext",
            variables: [.init(name: "stored", initialization: .value(.set([])), generatedSwiftType: "SetExpr<Color>", origin: .compiler)],
            actions: [], invariants: [], constraint: .equal(.setLiteral([.value(.string("green"))]), .variable("stored"))
        ).compile()
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        }
    }
}
