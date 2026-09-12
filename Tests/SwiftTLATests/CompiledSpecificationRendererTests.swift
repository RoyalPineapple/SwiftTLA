import Testing
@testable import SwiftTLA

@Suite("Compiled specification rendering")
struct CompiledSpecificationRendererTests {
    @Test("Structured operation syntax uses resolved operand positions and binding identities")
    func structuredOperationSyntax() throws {
        let binder = BinderID(ordinal: 0)
        let cases: [(ResolvedOperation, [String], String)] = [
            (.setMap(binder), ["item + 1", "Items"], "{item + 1 : item \\in Items}"),
            (.forAll(binder), ["Items", "item > 0"], "\\A item \\in Items : item > 0"),
            (.functionLiteral(binder), ["Items", "item + 1"], "[item \\in Items |-> item + 1]"),
            (.caseExpr(hasOtherwise: true), ["a", "b", "c", "d", "e"], "CASE a -> b [] c -> d [] OTHER -> e"),
            (.except, ["table", "key", "value"], "[table EXCEPT ![key] = value]"),
            (.foldFunction([binder]), ["body", "initial", "sequence"], "FoldFunction(LAMBDA item : body, initial, sequence)"),
            (.letValue(binder), ["value", "body"], "LET item == value IN body")
        ]
        for (operation, operands, expected) in cases {
            let syntax = try operation.tlaSyntax(operandCount: operands.count,
                binderName: { _ in "item" }, fieldName: { _ in "field" })
            let rendered = syntax.map { part in
                switch part {
                case .text(let text): text
                case .operand(let index): operands[index]
                }
            }.joined()
            #expect(rendered == expected)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try ResolvedOperation.caseExpr(hasOtherwise: false).tlaSyntax(
                operandCount: 3, binderName: { _ in "item" }, fieldName: { _ in "field" })
        }
    }

    @Test("Action and temporal grammar render resolved typed operands directly")
    func rendersResolvedOperands() throws {
        let compilation = try TLASpec(name: "ResolvedRendering", variables: [
            .init(name: "count", initial: .int(0))
        ], actions: [], invariants: []).compile()
        let variable = try #require(compilation.layout.variables.first?.id)
        let selected = BinderID(ordinal: 0)
        let saved = BinderID(ordinal: 1)
        let renderer = CompiledTLARenderer(layout: compilation.layout,
            bindings: .init(binders: [selected: "selected", saved: "saved"]),
            operators: compilation.semantics.operators)
        func literal(_ value: CompiledValue, type: CompiledValueType) -> ResolvedExpression {
            .init(operation: .value(value), resultType: type, children: [])
        }
        let one = literal(.integer(1), type: .int)
        let yes = literal(.boolean(true), type: .bool)
        let no = literal(.boolean(false), type: .bool)
        let domain = literal(.set([.integer(1)]), type: .set(.int))
        let action: CompiledActionExpr<ResolvedExpression> = .existsAction(selected, domain,
            .define(saved, one, .ifElse(yes,
                .and(.assign(variable, one), .unchanged(variable)),
                .or(.guard_(no), .assign(variable, one)))))
        func render(_ expression: ResolvedExpression) throws -> String {
            guard case .value(let value) = expression.operation else {
                throw CompiledEvaluationError.unresolvedOperator
            }
            return try value.rendered(using: compilation.layout).description
        }
        #expect(try renderer.action(action, renderExpression: render)
            == #"\E selected \in {1}: LET saved == 1 IN IF TRUE THEN ((count' = 1 /\ UNCHANGED count)) ELSE ((FALSE \/ count' = 1))"#)
        let trueQuery = CompiledStateQuery(expression: yes, enabledActions: [])
        let falseQuery = CompiledStateQuery(expression: no, enabledActions: [])
        let properties: [(CompiledTemporalExpr<CompiledStateQuery<ResolvedExpression>>, String)] = [
            (.always(trueQuery), "[]TRUE"), (.eventually(trueQuery), "<>TRUE"),
            (.alwaysEventually(trueQuery), "[]<>TRUE"), (.eventuallyAlways(trueQuery), "<>[]TRUE"),
            (.leadsTo(trueQuery, falseQuery), "(TRUE ~> FALSE)")
        ]
        for (property, expected) in properties {
            #expect(try renderer.temporal(property, renderExpression: render) == expected)
        }
    }

    @Test("Nested checked views render their operands once without capturing source names")
    func checkedViewsPreserveOperandOwnership() throws {
        let compilation = try TLASpec(name: "CheckedViews", variables: [
            .init(name: "_checkedValue", initial: .int(1))
        ], actions: [], invariants: []).compile()
        let variable = try #require(compilation.layout.variables.first?.id)
        let renderer = CompiledTLARenderer(layout: compilation.layout,
            bindings: .init(), operators: compilation.semantics.operators)
        let source = CompiledStateExpr.stateVariable(variable)
        #expect(try renderer.state(.assertView(source, .integer))
            == "(LET _checkedValue_ == _checkedValue IN CASE _checkedValue_ \\in Int -> _checkedValue_)")
        var nested = CompiledStateExpr.value(.integer(123456789))
        for _ in 0..<64 { nested = .assertView(nested, .integer) }
        let rendered = try renderer.state(nested)
        #expect(rendered.components(separatedBy: "123456789").count == 2)
        #expect(rendered.components(separatedBy: "IN CASE").count == 65)
        #expect(rendered.utf8.count < 20_000)
        // A shape's formal constants must also remain outside the generated binding.
        #expect(try renderer.state(.assertView(.value(.integer(1)),
            .finite(typeName: "Named", values: [.constant("_checkedValue")])))
            == "(LET _checkedValue_ == 1 IN CASE _checkedValue_ \\in {_checkedValue} -> _checkedValue_)")
    }

    @Test("compilation rejects a module name that requires renderer rewriting")
    func compilationRejectsInvalidModuleName() {
        for name in ["Invalid Root", "MODULE"] {
            do {
                _ = try TLASpec(name: name, variables: [], actions: [], invariants: []).compile()
                Issue.record("Expected an invalid module name diagnostic for \(name).")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.code == .invalidSpecificationName)
                #expect(diagnostic.stage == .validation)
            } catch {
                Issue.record("Expected CompilationDiagnostic, got \(error).")
            }
        }
    }

    @Test("an invalid closure cannot render a bundle")
    func invalidClosureHasNoRenderedOutcome() throws {
        let invalid = TLASpec(
            name: "InvalidRoot",
            variables: [],
            actions: [],
            invariants: [],
            importConfigurations: [.init(moduleName: "Missing", replacements: [])]
        )
        #expect(throws: CompilationDiagnostic.self) {
            try invalid.compile().render().tlaBundle
        }
    }

    @Test("rendering carries each shared dependency and its source ownership once")
    func renderDeduplicatesClosureDependencies() throws {
        let support = TLASpec(name: "Support", variables: [], actions: [], invariants: [])
        let left = TLASpec(name: "Left", variables: [], actions: [], invariants: [], imports: [support])
        let right = TLASpec(name: "Right", variables: [], actions: [], invariants: [], imports: [support])
        let root = TLASpec(name: "Root", variables: [], actions: [], invariants: [], imports: [left, right])

        let bundle = try root.compile().render().tlaBundle

        #expect(bundle.files.map(\.name) == ["Support", "Left", "Right", "Root"])
        #expect(Set(bundle.files.map(\.name)).count == bundle.files.count)
        guard case let .compiled(_, ownership, dependencies) = bundle.provenance else {
            Issue.record("A compiled renderer produced an external bundle.")
            return
        }
        #expect(ownership.map(\.structuralPath) == [
            ["Root", "Left", "Support"], ["Root", "Left"], ["Root", "Right"], ["Root"]
        ])
        #expect(dependencies.map(\.importingModule) == ["Root", "Left", "Root", "Right"])
        #expect(dependencies.map(\.importedModule) == ["Left", "Support", "Right", "Support"])
    }

    @Test("authored PlusCal presentation uses the compiled bundle")
    func authoredPlusCalUsesCompiledBoundary() throws {
        let support = TLASpec(name: "Support", variables: [], actions: [], invariants: [])
        let specification = TLASpec("Authored") {
            Import(support)
            Algorithm("Authored", scoped: { scope in
                let value = scope.sharedVar("value", initial: 0)
                Do(TestControlLabel.stay) { Assign(value, to: value.expr) }
            })
        }
        let compilation = try specification.compile()

        let bundle = try compilation.render().plusCalBundle()
        let directBundle = try compilation.render().tlaBundle
        #expect(bundle.root.tla.contains("--algorithm Authored"))
        #expect(bundle.root.cfg == directBundle.root.cfg)
        #expect(bundle.imports.map(\.name) == ["Support"])
        guard case .compiled = bundle.provenance else {
            Issue.record("A compiled authored PlusCal bundle lost its provenance.")
            return
        }

    }

    @Test("authored PlusCal export requires one canonical Algorithm root")
    func authoredPlusCalRejectsNonAlgorithmRoot() throws {
        let compilation = try TLASpec(
            name: "DirectOnly", variables: [], actions: [], invariants: []
        ).compile()

        #expect(throws: CompilationDiagnostic.self) {
            try compilation.render().plusCalBundle()
        }
    }

    @Test("compilation rejects malformed CASE expressions")
    func compilationRejectsMalformedCases() {
        let cases: [(StateExpr, String)] = [
            (.caseExpr([.bool(true)], nil), "an unmatched CASE branch"),
            (.caseExpr([], nil), "no CASE branches"),
            (.caseExpr([], .int(1)), "no CASE branches")
        ]

        for (index, testCase) in cases.enumerated() {
            let specification = TLASpec(
                name: "MalformedCase\(index)",
                variables: [],
                actions: [],
                invariants: [],
                formalOperatorDefinitions: [
                    .init(name: "Choice", parameters: [], body: testCase.0)
                ]
            )
            do {
                _ = try specification.compile()
                Issue.record("Expected malformed CASE expression \(index) to fail compilation.")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.code == .invalidFormalDeclaration)
                #expect(diagnostic.stage == .validation)
                #expect(diagnostic.actual == testCase.1)
            } catch {
                Issue.record("Expected CompilationDiagnostic, got \(error).")
            }
        }
    }

}
