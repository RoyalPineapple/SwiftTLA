import Testing
@testable import SwiftTLA

@Suite struct NativeUnionResolutionTests {
    private var metadata: NativeSourceTypeMetadata {
        .init(aliases: ["Choice": "OneOf<Missing,OneOf<Node,Set<Node>>>"],
              enums: ["Missing": [.constant("none")], "Node": [.int(1), .int(2)]],
              finiteViewDomains: ["Missing": [.constant("none")], "Node": [.int(1), .int(2)]])
    }

    @Test("nested unions keep one finite scalar representation and disjoint structural alternatives")
    func normalizedStorage() throws {
        let program = try resolve(type: "Choice", initial: .int(1))
        let type = try #require(program.variableTypes.values.first)
        #expect(type == .union([.finite([.integer(1), .integer(2), .constant("none")]), .set(.named("Node"))]))
        let checker = try typeChecker()
        #expect(checker.canProjectRead(.named("Node"), to: type))
        #expect(!checker.canProjectRead(.int, to: type))
    }

    @Test("union collection constructors retain validated member evidence")
    func collectionConstructor() throws {
        let program = try resolve(type: "Choice", initial: .setLiteral([.int(1)]))
        let root = try #require(program.initializations.values.first)
        #expect(program[root].computationType == .set(.named("Node")))
        #expect(program[program[root].children[0]].resultType == .named("Node"))
        #expect(throws: CompilationDiagnostic.self) {
            try resolve(type: "Choice", initial: .setLiteral([.int(3)]))
        }
    }

    @Test("set algebra retains its collection type inside a union", arguments: [
        StateExpr.union(.setLiteral([.int(1)]), .setLiteral([.int(2)])),
        StateExpr.intersection(.setLiteral([.int(1)]), .setLiteral([])),
        StateExpr.setDifference(.setLiteral([.int(1)]), .setLiteral([.int(2)])),
        StateExpr.union(.setLiteral([]), .setLiteral([]))
    ])
    func collectionOperations(expression: StateExpr) throws {
        let program = try resolve(type: "Choice", initial: expression)
        let root = try #require(program.initializations.values.first)
        #expect(program[root].computationType == .set(.named("Node")))
        #expect(program[root].resultType == program.variableTypes.values.first)
        for child in program[root].children {
            #expect(program[child].resultType == .set(.named("Node")))
        }
    }

    @Test("sequence constructors inside unions preserve nominal member types")
    func sequenceConstructor() throws {
        let type = "OneOf<Missing,TupleExpr<Node>>"
        let program = try resolve(type: type, initial: .tupleLiteral([.int(1), .int(2)]))
        let root = try #require(program.initializations.values.first)
        #expect(program[root].computationType == .array(.named("Node")))
        #expect(program[root].children.count == 2)
        for child in program[root].children {
            #expect(program[child].resultType == .named("Node"))
        }
        #expect(throws: CompilationDiagnostic.self) {
            try resolve(type: type, initial: .tupleLiteral([.int(3)]))
        }
    }

    @Test("finite-only unions retain deduplicated finite storage")
    func finiteStorage() throws {
        let program = try resolve(type: "OneOf<Node,Node>", initial: .int(1))
        #expect(program.variableTypes.values.first == .finite([.integer(1), .integer(2)]))
    }

    @Test("overlapping structural union domains are rejected")
    func overlappingCollections() throws {
        #expect(throws: CompilationDiagnostic.self) {
            try resolve(type: "OneOf<Set<Node>,Set<Missing>>", initial: .setLiteral([]))
        }
    }

    @Test("an unrestricted scalar absorbs overlapping finite union members")
    func overlappingScalars() throws {
        let program = try resolve(type: "OneOf<Node,Int>", initial: .int(1))
        #expect(program.variableTypes.values.first == .int)
    }

    @Test("an explicit view narrows without approving an implicit conversion")
    func explicitView() throws {
        let shape = FormalValueShape.finite(typeName: "Node", values: [.int(1), .int(2)])
        let program = try resolve(type: "OneOf<Node,Missing>", initial: .value(.constant("none")),
                                  invariant: .equal(.assertView(.variable("value"), shape), .int(1)))
        let root = try #require(program.invariants.values.first)
        let view = program[program[root].children[0]]
        #expect(view.computationType == .named("Node"))
        let source = program[view.children[0]].resultType
        let checker = try typeChecker()
        #expect(!checker.canProjectRead(source, to: .named("Node")))
    }

    @Test("source witness structure agrees with the declared union before native normalization")
    func sourceShape() throws {
        #expect(try metadata.formalShape(for: "Choice") == .union(
            .finite(typeName: "Missing", values: [.constant("none")]),
            .union(.finite(typeName: "Node", values: [.int(1), .int(2)]),
                   .set(.finite(typeName: "Node", values: [.int(1), .int(2)])))))
        #expect(!(try metadata.formalShape(for: "Function<Node,Int>")).isSupported)
    }

    @Test("a restricted finite witness keeps excluded enum cases outside the checked view")
    func restrictedFiniteWitness() throws {
        let shape = FormalValueShape.finite(typeName: "Node", values: [.int(1)])
        let program = try resolve(type: "Node", initial: .int(2),
            invariant: .equal(.assertView(.variable("value"), shape), .int(1)))
        let root = try #require(program.invariants.values.first)
        let view = program[program[root].children[0]]
        #expect(view.computationType == .finite([.integer(1)]))
        let checker = try typeChecker()
        #expect(!checker.canProjectRead(.named("Node"), to: view.computationType))
        #expect(checker.canProjectRead(view.computationType, to: .named("Node")))
    }

    @Test("an enum case table does not imply an explicit finite-view witness")
    func enumWithoutWitness() throws {
        let source = NativeSourceTypeMetadata(enums: ["Plain": [.int(1)]])
        #expect(!(try source.formalShape(for: "Plain")).isSupported)
    }

    private func typeChecker() throws -> NativeTypeInference {
        let specification = TLASpec(name: "UnionConversions", variables: [], actions: [], invariants: [])
        return try NativeTypeInference(plan: .init(compilation: specification.compile()), sourceTypes: metadata)
    }

    private func resolve(type: String, initial: StateExpr, invariant: StateExpr? = nil) throws -> NativeResolvedProgram {
        let specification = TLASpec(name: "UnionEvidence", variables: [
            .init(name: "value", initialization: .expression(initial), generatedSwiftType: type, origin: .compiler)
        ], actions: [], invariants: invariant.map { [.init(name: "View", body: $0)] } ?? [])
        return try .init(plan: .init(compilation: specification.compile()), sourceTypes: metadata)
    }
}
