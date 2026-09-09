import Testing
@testable import SwiftTLA

struct NativeTypeEvidenceTests {
    @Test("Empty collections acquire element evidence from transition writes")
    func emptyCollectionsUseAssignmentEvidence() throws {
        let compilation = try TLASpec(
            name: "EmptyCollectionEvidence",
            variables: [.init(name: "items", initialization: .value(.set([])), origin: .compiler)],
            actions: [.init(name: "fill", body: .assign(.named("items"), .setLiteral([.int(1)])))],
            invariants: []
        ).compile()

        let evidence = try NativeTypeInference(compilation: compilation)
        #expect(evidence.variables[compilation.layout.variables[0].id] == .set(.int))
    }

    @Test("Source collection wrappers project to native Swift shapes")
    func wrapperHintsConstrainEmptyInitializers() throws {
        let compilation = try TLASpec(
            name: "CollectionShapeEvidence",
            variables: [.init(name: "items", initialization: .value(.tuple([])), generatedSwiftType: "TupleExpr<Int>", origin: .compiler)],
            actions: [], invariants: []
        ).compile()

        let evidence = try NativeTypeInference(compilation: compilation)
        #expect(evidence.variables[compilation.layout.variables[0].id] == .array(.int))
        #expect(evidence.variables[compilation.layout.variables[0].id]?.swiftType == "[Int]")
    }

    @Test("Hidden algorithm control is retained as native control evidence")
    func hiddenControlIsNotAString() throws {
        let compilation = try TLASpec("NativeControl", scoped: { scope in
            let value = scope.sharedVar("value", initial: 0)
            Algorithm("NativeControl") {
                Do(TestControlLabel.advance) { Assign(value, to: value + 1) }
                Do(TestControlLabel.done) { Stop() }
            }
        }).compile()

        let evidence = try NativeTypeInference(compilation: compilation)
        let control = try #require(compilation.layout.variables.first { $0.declaration.origin == .programCounter })
        #expect(evidence.variables[control.id] == .control)
    }

    @Test("Constraints and writes must agree with native variable evidence")
    func incompatibleShapesAreRejected() throws {
        let compilation = try TLASpec(
            name: "IncompatibleEvidence",
            variables: [.init(name: "value", initialization: .value(.int(0)), origin: .compiler)],
            actions: [.init(name: "change", body: .assign(.named("value"), .value(.bool(true))))],
            invariants: []
        ).compile()
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(compilation: compilation)
        }
        let invalidConstraint = try TLASpec(
            name: "ConstraintEvidence",
            variables: [.init(name: "value", initialization: .value(.int(0)), origin: .compiler)],
            actions: [], invariants: [], constraint: .variable("value")
        ).compile()
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(compilation: invalidConstraint)
        }
    }

    @Test("Formal model atoms remain distinct from string literals")
    func atomAndStringHaveDistinctNativeEvidence() throws {
        let compilation = try TLASpec(
            name: "AtomEvidence",
            variables: [.init(name: "value", initialization: .value(.constant("member")), origin: .compiler)],
            actions: [], invariants: []
        ).compile()
        let evidence = try NativeTypeInference(compilation: compilation)
        #expect(try evidence.type(of: .value(.constant("member"))) == .atom)
        #expect(try evidence.type(of: .value(.string("member"))) == .string)
    }
    @Test("Record wrappers obtain field evidence from writes into empty sequences")
    func recordSchemaPayloadUsesResolvedFields() throws {
        let compilation = try TLASpec(
            name: "RecordPayloadEvidence",
            variables: [.init(name: "items", initialization: .value(.tuple([])), generatedSwiftType: "TupleExpr<Record<OperationSchema>>", origin: .compiler)],
            actions: [.init(name: "append", body: .assign(.named("items"), .tupleAppend(.variable("items"), .value(.record(["count": .int(1)])))))],
            invariants: []
        ).compile()

        let evidence = try NativeTypeInference(compilation: compilation)
        #expect(evidence.variables[compilation.layout.variables[0].id] == .array(.record([.init(name: "count", type: .int)])))
    }

    @Test("Enum literal context does not coerce enum storage into arithmetic integers")
    func enumEvidenceIsContextualAndNotNumeric() throws {
        let compilation = try TLASpec(
            name: "EnumEvidence",
            variables: [.init(name: "member", initialization: .value(.string("a")), generatedSwiftType: "Member", origin: .compiler)],
            actions: [], invariants: []
        ).compile()

        let evidence = try NativeTypeInference(compilation: compilation)
        let member = CompiledStateExpr.stateVariable(compilation.layout.variables[0].id)
        let literal = CompiledStateExpr.value(.string("a"))
        for expression in [CompiledStateExpr.equal(literal, member), .equal(member, literal)] {
            let checked = try evidence.resolutionScope(expression, expected: .bool)
            #expect(checked.children.map(\.resultType) == [.named("Member"), .named("Member")])
        }
        #expect(throws: CompilationDiagnostic.self) {
            try evidence.type(of: .add(member, .value(.integer(1))))
        }
    }

    @Test("Aliases and schema fields use shared source metadata without opaque values")
    func schemaAliasResolvesFiniteAtomUnion() throws {
        let metadata = NativeSourceTypeMetadata(
            aliases: ["Value": "OneOf<Transaction, NoValue>"],
            records: ["OperationSchema": [.init(sourceName: "value", name: "value", swiftType: "Value")]],
            enums: ["Transaction": [.constant("t1")], "NoValue": [.constant("NoVal")]]
        )
        let compilation = try TLASpec(
            name: "SchemaAliasEvidence",
            variables: [.init(name: "operations", initialization: .value(.tuple([])), generatedSwiftType: "TupleExpr<Record<OperationSchema>>", origin: .compiler)],
            actions: [], invariants: []
        ).compile()

        let evidence = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        #expect(evidence.variables[compilation.layout.variables[0].id] == .array(.record([.init(name: "value", type: .finite([.constant("NoVal"), .constant("t1")]))])))
        #expect(evidence.namedRepresentations["Transaction"] == .atom)
    }

    @Test("Cyclic source aliases fail at compiler admission")
    func cyclicAliasesAreRejected() throws {
        let compilation = try TLASpec(
            name: "CyclicAliasEvidence",
            variables: [.init(name: "value", initialization: .value(.int(0)), generatedSwiftType: "First", origin: .compiler)],
            actions: [], invariants: []
        ).compile()
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(compilation: compilation, sourceTypes: .init(aliases: ["First": "Second", "Second": "First"]))
        }
    }

    @Test("Tuple projection constrains only the selected unresolved member")
    func heterogeneousTupleProjectionDoesNotHomogenizeMembers() throws {
        let evidence = try NativeTypeInference(compilation: canonicalTestSpec().compile())
        let first = BinderID(ordinal: 500)
        let second = BinderID(ordinal: 501)
        let pair = CompiledStateExpr.tupleLiteral([.boundValue(first), .boundValue(second)])
        let expression = CompiledStateExpr.and(
            .lessOrEqual(.value(.integer(0)), .tupleAccess(pair, 1)),
            .equal(.boundValue(second), .value(.string("value")))
        )
        #expect(try evidence.type(of: expression) == .bool)
    }

    @Test("An unknown record schema cannot masquerade as a concrete empty record")
    func missingSchemaRequiresActualFieldEvidence() throws {
        let compilation = try TLASpec(
            name: "MissingRecordEvidence",
            variables: [.init(name: "items", initialization: .value(.tuple([])), generatedSwiftType: "TupleExpr<Record<MissingSchema>>", origin: .compiler)],
            actions: [], invariants: []
        ).compile()
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(compilation: compilation)
        }
    }

    @Test("Finite aliases exclude unrelated atoms and collapse equal member domains")
    func finiteAliasPreservesItsExactDomain() throws {
        let metadata = NativeSourceTypeMetadata(
            aliases: ["Value": "OneOf<Left, Right>"],
            enums: ["Left": [.constant("same"), .constant("left")], "Right": [.constant("same"), .constant("right")], "Foreign": [.constant("outside")]]
        )
        let compilation = try TLASpec(
            name: "FiniteUnionEvidence",
            variables: [.init(name: "value", initialization: .value(.constant("left")), generatedSwiftType: "Value", origin: .compiler)],
            actions: [], invariants: []
        ).compile()

        let evidence = try NativeTypeInference(compilation: compilation, sourceTypes: metadata)
        let domain = NativeType.finite([.constant("left"), .constant("right"), .constant("same")])
        #expect(evidence.variables[compilation.layout.variables[0].id] == domain)
        #expect(try evidence.type(of: .value(.constant("right")), expected: domain) == domain)
        #expect(throws: CompilationDiagnostic.self) {
            try evidence.type(of: .value(.constant("outside")), expected: domain)
        }
    }

    @Test("Literal choice domains provide explicit evidence for finite union lifting")
    func literalBinderLiftRequiresSubsetProof() throws {
        let evidence = try NativeTypeInference(compilation: canonicalTestSpec().compile())
        let binder = BinderID(ordinal: 600)
        let admitted = NativeType.finite([.constant("left"), .constant("right")])
        let valid = CompiledStateExpr.setMap(.boundValue(binder), binder, .value(.set([.constant("left")])))
        #expect(try evidence.type(of: valid, expected: .set(admitted)) == .set(admitted))
        let invalid = CompiledStateExpr.setMap(.boundValue(binder), binder, .value(.set([.constant("outside")])))
        #expect(throws: CompilationDiagnostic.self) {
            try evidence.type(of: invalid, expected: .set(admitted))
        }
    }

    @Test("Function choice binders refine key and finite value domains together")
    func compoundBinderRefinesFromItsConstructedDomain() throws {
        let evidence = try NativeTypeInference(
            compilation: canonicalTestSpec().compile(),
            sourceTypes: .init(enums: ["Key": [.constant("key")]])
        )
        let binder = BinderID(ordinal: 601)
        let value = NativeType.finite([.constant("missing"), .constant("present")])
        let functions = CompiledStateExpr.functionSet(.value(.set([.constant("key")])), .value(.set([.constant("missing")])))
        let selected = CompiledStateExpr.setMap(.boundValue(binder), binder, functions)
        let expected = NativeType.set(.dictionary(.named("Key"), value))
        #expect(try evidence.type(of: selected, expected: expected) == expected)
    }

    @Test("Tuple source evidence carries the selected native enum representation")
    func projectedLiteralRetainsNamedAndFiniteFieldTypes() throws {
        let evidence = try NativeTypeInference(compilation: canonicalTestSpec().compile(), sourceTypes: .init(enums: ["Process": [.int(1)]]))
        let namedTuple = CompiledStateExpr.tupleLiteral([.value(.integer(1)), .value(.string("other"))])
        let namedRead = try evidence.resolutionScope(.tupleAccess(namedTuple, 1), expected: .named("Process"))
        #expect(namedRead.children.map(\.resultType) == [.tuple([.named("Process"), .string])])
        let finite = NativeType.finite([.constant("member")])
        let finiteTuple = CompiledStateExpr.value(.tuple([.constant("member"), .integer(1)]))
        let finiteRead = try evidence.resolutionScope(.tupleAccess(finiteTuple, 1), expected: finite)
        #expect(finiteRead.children.map(\.resultType) == [.tuple([finite, .int])])
    }

    @Test("Recursive record schema metadata fails with a typed diagnostic")
    func recursiveSchemaGraphsAreRejected() throws {
        let compilation = try TLASpec(name: "RecursiveSchemaEvidence", variables: [.init(name: "nodes", initialization: .value(.tuple([])), generatedSwiftType: "TupleExpr<Record<Node>>", origin: .compiler)], actions: [], invariants: []).compile()
        let graphs: [[String: [NativeSourceRecordField]]] = [
            ["Node": [.init(sourceName: "children", name: "children", swiftType: "TupleExpr<Record<Node>>")]],
            ["Node": [.init(sourceName: "child", name: "child", swiftType: "Record<Other>")], "Other": [.init(sourceName: "parent", name: "parent", swiftType: "Record<Node>")]]
        ]
        for records in graphs {
            #expect(throws: CompilationDiagnostic.self) {
                try NativeTypeInference(compilation: compilation, sourceTypes: .init(records: records))
            }
        }
    }

    @Test("Raw scalar reads preserve a binder's native enum representation")
    func enumBinderIsNotDemotedByLaterIntegerUse() throws {
        let domain = StateExpr.setLiteral([.int(1), .int(2)])
        let body = StateExpr.forAll(domain, "process", .and(
            .equal(.functionApply(.variable("values"), .variable("process")), .int(0)),
            .lessThan(.variable("process"), .int(3))
        ))
        let compilation = try TLASpec(
            name: "StableEnumBinder",
            variables: [.init(name: "values", initialization: .value(.function([.int(1): .int(0), .int(2): .int(0)])), generatedSwiftType: "Function<Process, Int>", origin: .compiler)],
            actions: [], invariants: [.init(name: "Valid", body: body)]
        ).compile()

        let evidence = try NativeTypeInference(compilation: compilation, sourceTypes: .init(enums: ["Process": [.int(1), .int(2)]]))
        guard case .forAll(_, let binder, _) = compilation.semantics.invariants[0].body else {
            Issue.record("Expected the invariant's resolved quantifier")
            return
        }
        #expect(evidence.bindings[binder] == .named("Process"))
        #expect(try evidence.type(of: .boundValue(binder), expected: .int) == .int)
        #expect(evidence.bindings[binder] == .named("Process"))
    }

}
