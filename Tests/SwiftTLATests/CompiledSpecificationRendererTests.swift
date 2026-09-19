import Foundation
import Testing
@testable import SwiftTLA

@Suite("Compiled specification rendering")
struct CompiledSpecificationRendererTests {
    @Test("Independent record comprehensions retain their exact Cartesian domain at serialization")
    func rendersCartesianRecordDomains() throws {
        let compiled = try TLASpec(name: "RecordDomains", variables: [], actions: [], invariants: []).compile()
        let first = BinderID(ordinal: 0)
        let second = BinderID(ordinal: 1)
        let maximum = BinderID(ordinal: 2)
        let captured = OperatorID(ordinal: 0)
        let renderer = CompiledTLARenderer(moduleName: "RecordDomains", reservedNames: [], layout: compiled.layout,
            bindings: .init(operatorNames: [captured: "Captured"],
                binders: [first: "first", second: "second", maximum: "maximum"]),
            operators: compiled.semantics.operators, actions: [], functions: [])
        let domain = CompiledExpression(operation: .integerRange,
            children: [.value(.integer(0)), .boundValue(maximum)])
        let record = CompiledExpression(operation: .recordLiteral(["right", "left"]),
            children: [.boundValue(second), .boundValue(first)])
        func product(_ record: CompiledExpression, outer: CompiledExpression,
                     inner: CompiledExpression) -> CompiledExpression {
            .init(operation: .unionAll, children: [
                .setMap(.setMap(record, second, inner), first, outer)
            ])
        }
        #expect(try renderer.state(product(record, outer: domain, inner: domain))
            == "[right: 0..maximum, left: 0..maximum]")
        let empty = CompiledExpression.value(.set([]))
        #expect(try renderer.state(product(record, outer: empty, inner: domain))
            == "[right: 0..maximum, left: {}]")
        let converted = CompiledExpression(operation: .convert, children: [record])
        #expect(try renderer.state(product(converted, outer: domain, inner: empty))
            == "[right: {}, left: 0..maximum]")

        let dependent = CompiledExpression(operation: .integerRange,
            children: [.value(.integer(0)), .boundValue(first)])
        let fallible = CompiledExpression(operation: .integerRange, children: [
            .value(.integer(0)), .init(operation: .divide, children: [.value(.integer(1)), .value(.integer(0))])
        ])
        for inner in [dependent, fallible, .operatorReference(captured)] {
            #expect(try renderer.state(product(record, outer: empty, inner: inner)).hasPrefix("UNION "))
        }
        let duplicate = CompiledExpression(operation: .recordLiteral(["right", "left"]),
            children: [.boundValue(first), .boundValue(first)])
        let dropped = CompiledExpression(operation: .recordLiteral(["left"]), children: [.boundValue(first)])
        let transformed = CompiledExpression(operation: .recordLiteral(["right", "left"]), children: [
            .init(operation: .add, children: [.boundValue(second), .value(.integer(1))]), .boundValue(first)
        ])
        for body in [duplicate, dropped, transformed] {
            #expect(try renderer.state(product(body, outer: domain, inner: domain)).hasPrefix("UNION "))
        }
    }

    @Test("Set syntax has the same deterministic ordering as set values without reordering tuples")
    func canonicalSetSerialization() throws {
        let compilation = try TLASpec(name: "Sets", variables: [], actions: [], invariants: []).compile()
        let renderer = CompiledTLARenderer(moduleName: "Sets", reservedNames: [], layout: compilation.layout,
            bindings: .init(), operators: compilation.semantics.operators, actions: [], functions: [])
        let one = CompiledExpression.value(.integer(1))
        let two = CompiledExpression.value(.integer(2))
        let empty = CompiledExpression(operation: .setLiteral, children: [])
        let pair = CompiledExpression(operation: .setLiteral, children: [two, one])
        let nested = CompiledExpression(operation: .setLiteral, children: [empty, pair])
        let value = CompiledExpression.value(.set([.set([]), .set([.integer(1), .integer(2)])]))
        #expect(try renderer.state(nested) == renderer.state(value))
        let tuple = CompiledExpression(operation: .tupleLiteral, children: [two, pair, one])
        #expect(try renderer.state(tuple) == "<<2, {1, 2}, 1>>")
        #expect(try renderer.state(empty) == "{}")
    }

    @Test("Enabledness references use the resolved action declaration name")
    func rendersResolvedActionNames() throws {
        let compilation = try TLASpec(name: "ResolvedActionNames", variables: [
            .init(name: "count", initial: .int(0))
        ], actions: [
            .init(name: "advance-step", body: .unchanged(.named("count"))),
            .init(name: "advance_step", body: .unchanged(.named("count")))
        ], invariants: [
            .init(name: "CanAdvance", body: .enabledAction("advance-step")),
            .init(name: "CanAlsoAdvance", body: .enabledAction("advance_step"))
        ]).compile()
        let rendered = try compilation.render().tlaBundle.tla
        #expect(rendered.contains("advance_step =="))
        #expect(rendered.contains("advance_step__2 =="))
        #expect(rendered.contains("CanAdvance == ENABLED advance_step\n"))
        #expect(rendered.contains("CanAlsoAdvance == ENABLED advance_step__2\n"))
    }

    @Test("Action dependencies are declared before their enabledness consumers")
    func declaresActionsBeforeEnablednessConsumers() throws {
        let compilation = try TLASpec(name: "EnablednessOrder", variables: [
            .init(name: "count", initial: .int(0))
        ], actions: [
            .init(name: "advance", body: .and(.guard_(.enabledAction("ready")),
                .assign(.named("count"), .value(.int(1))))),
            .init(name: "ready", body: .unchanged(.named("count")))
        ], invariants: [.init(name: "CanAdvance", body: .enabledAction("advance"))],
            constraint: .enabledAction("ready")).compile()
        let rendered = try compilation.render().tlaBundle.tla
        let ready = try #require(rendered.range(of: "ready =="))
        let advance = try #require(rendered.range(of: "advance =="))
        let invariant = try #require(rendered.range(of: "CanAdvance =="))
        let constraint = try #require(rendered.range(of: "StateConstraint =="))
        #expect(ready.lowerBound < advance.lowerBound)
        #expect(advance.lowerBound < invariant.lowerBound)
        #expect(ready.lowerBound < constraint.lowerBound)
    }

    @Test("Parameterized enabledness and whole-action fairness quantify finite domains")
    func quantifiesActionParameters() throws {
        let compilation = try TLASpec(name: "ParameterizedReferences", variables: [
            .init(name: "count", initial: .int(0))
        ], actions: [
            .init(name: "advance", body: .assign(.named("count"), .variable("amount")),
                bindings: [.init(name: "amount", values: [.int(1), .int(2)])])
        ], invariants: [.init(name: "CanAdvance", body: .enabledAction("advance"))],
            fairness: [.weakFairness("advance"), .strongFairness("advance"),
                .weakFairnessActionCall(.init(name: "advance", arguments: [.int(1)]))]).compile()
        let binding = try #require(compilation.semantics.behavior.actions.first?.bindings.first)
        let parameter = try #require(compilation.bindings.binderName(binding.binder))
        let action = "(\\E \(parameter) \\in {1, 2}: advance(\(parameter)))"
        let rendered = try compilation.render().tlaBundle.tla
        #expect(rendered.contains("CanAdvance == ENABLED \(action)"))
        #expect(rendered.contains("WF_count(\(action))"))
        #expect(rendered.contains("SF_count(\(action))"))
        #expect(rendered.contains("WF_count(advance__0)"))
    }

    @Test("Model values cannot alias module variables")
    func rejectsModelValueDeclarationCollision() throws {
        #expect(throws: CompilationDiagnostic.self) {
            _ = try TLASpec(name: "Collision", variables: [
                .init(name: "d1", initial: .constant("d1"))
            ], actions: [], invariants: []).compile()
        }
    }

    @Test("Quantifier binders cannot capture model values discovered in their bodies")
    func avoidsModelValueCapture() throws {
        let body = StateExpr.forAll(.value(.set([.constant("d2")])), "d1",
            .equal(.variable("d1"), .value(.constant("d1"))))
        let compiled = try TLASpec(name: "Capture", variables: [], actions: [], invariants: [],
            formalOperatorDefinitions: [.init(name: "Check", parameters: [], body: body)]).compile()
        let name = try #require(compiled.bindings.binders.values.first)
        #expect(name != "d1")
        #expect(try compiled.render().tlaBundle.tla.contains("(\(name) = d1)"))
    }

    @Test("Model values in nested literals are declared and assigned once", arguments: [
        TLAValue.constant("d1"),
        .set([.constant("d1")]),
        .tuple([.constant("d1"), .constant("d1")]),
        .record(TLARecord([.init("value", .constant("d1"))])),
        .function([.constant("d1"): .set([.constant("d1")])])
    ])
    func declaresNestedModelValues(value: TLAValue) throws {
        let rendered = try TLASpec(name: "ModelValues", variables: [
            .init(name: "value", initial: value)
        ], actions: [], invariants: []).compile().render()
        #expect(rendered.tlaBundle.tla.components(separatedBy: "CONSTANTS d1\n").count == 2)
        #expect(rendered.tlaBundle.cfg.components(separatedBy: "CONSTANT d1 = d1\n").count == 2)
        #expect(try rendered.tlaBundle(checking: [], checkDeadlock: false).cfg.contains("CONSTANT d1 = d1\n"))
    }

    @Test("Structured operation syntax uses resolved operand positions and binding identities")
    func structuredOperationSyntax() throws {
        let binder = BinderID(ordinal: 0)
        let cases: [(CompiledOperation, [String], String)] = [
            (.setMap(binder), ["item + 1", "Items"], "{item + 1 : item \\in Items}"),
            (.forAll(binder), ["Items", "item > 0"], "(\\A item \\in Items : item > 0)"),
            (.functionLiteral(binder), ["Items", "item + 1"], "[item \\in Items |-> item + 1]"),
            (.caseExpr(hasOtherwise: true), ["a", "b", "c", "d", "e"], "CASE a -> b [] c -> d [] OTHER -> e"),
            (.except, ["table", "key", "value"], "[table EXCEPT ![key] = value]"),
            (.foldFunction([binder]), ["body", "initial", "sequence"], "FoldFunction(LAMBDA item : body, initial, sequence)"),
            (.letValue(binder), ["value", "body"], "(LET item == value IN body)")
        ]
        for (operation, operands, expected) in cases {
            let syntax = try operation.tlaSyntax(operandCount: operands.count,
                binderName: { _ in "item" })
            let rendered = syntax.map { part in
                switch part {
                case .text(let text): text
                case .operand(let index): operands[index]
                }
            }.joined()
            #expect(rendered == expected)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledOperation.caseExpr(hasOtherwise: false).tlaSyntax(
                operandCount: 3, binderName: { _ in "item" })
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
        let renderer = CompiledTLARenderer(moduleName: "ResolvedRendering", reservedNames: [], layout: compilation.layout,
            bindings: .init(binders: [selected: "selected", saved: "saved"]),
            operators: compilation.semantics.operators, actions: compilation.semantics.behavior.actions, functions: [])
        func literal(_ value: CompiledValue, type: CompiledValueType) -> CompiledExpression {
            .init(operation: .value(value), resultType: type, children: [])
        }
        let one = literal(.integer(1), type: .int)
        let yes = literal(.boolean(true), type: .bool)
        let no = literal(.boolean(false), type: .bool)
        let domain = literal(.set([.integer(1)]), type: .set(.int))
        let action: CompiledActionExpr = .existsAction(selected, domain,
            .define(saved, one, .ifElse(yes,
                .and(.assign(variable, one), .unchanged(variable)),
                .or(.guard_(no), .assign(variable, one)))))
        #expect(try renderer.action(action)
            == #"(\E selected \in {1}: (LET saved == 1 IN (IF TRUE THEN ((count' = 1 /\ UNCHANGED count)) ELSE ((FALSE \/ count' = 1)))))"#)
        let exists = CompiledExpression(operation: .exists(selected), resultType: .bool, children: [domain, yes])
        #expect(try renderer.action(.guard_(exists)) == #"((\E selected \in {1} : TRUE)) = TRUE"#)
        let trueQuery = CompiledStateQuery(expression: yes, enabledActions: [])
        let falseQuery = CompiledStateQuery(expression: no, enabledActions: [])
        let properties: [(TemporalCondition<CompiledStateQuery>, String)] = [
            (.always(trueQuery), "[]TRUE"), (.eventually(trueQuery), "<>TRUE"),
            (.alwaysEventually(trueQuery), "[]<>TRUE"), (.eventuallyAlways(trueQuery), "<>[]TRUE"),
            (.leadsTo(trueQuery, falseQuery), "(TRUE ~> FALSE)")
        ]
        for (property, expected) in properties {
            #expect(try renderer.temporal(property) == expected)
        }
    }

    @Test("Sibling lexical scopes stay separate in rendered state and action expressions")
    func delimitsSiblingLexicalScopes() throws {
        let compiled = try TLASpec(name: "LexicalScopes", variables: [], actions: [], invariants: []).compile()
        let binder = BinderID(ordinal: 0)
        let renderer = CompiledTLARenderer(moduleName: "LexicalScopes", reservedNames: [], layout: compiled.layout,
            bindings: .init(binders: [binder: "item"]), operators: compiled.semantics.operators,
            actions: [], functions: [])
        let domain = CompiledExpression.value(.set([.integer(1)]))
        let yes = CompiledExpression.value(.boolean(true))
        for operation in [CompiledOperation.forAll(binder), .exists(binder), .choose(binder), .letValue(binder)] {
            let expression = CompiledExpression(operation: operation, children: [domain, yes])
            let scoped = try renderer.state(expression)
            #expect(scoped.first == "(" && scoped.last == ")")
            #expect(try renderer.state(.init(operation: .equal, children: [expression, expression]))
                == "(\(scoped) = \(scoped))")
        }
        let guardAction = CompiledActionExpr.guard_(yes)
        for action in [CompiledActionExpr.existsAction(binder, domain, guardAction),
            .define(binder, yes, guardAction), .ifElse(yes, guardAction, guardAction)] {
            let scoped = try renderer.action(action)
            #expect(scoped.first == "(" && scoped.last == ")")
            #expect(try renderer.action(.and(action, action)) == "(\(scoped) /\\ \(scoped))")
        }
        let local = StateExpr.letIn([LocalOperator("item", body: .bool(true))], .variable("item"))
        let specification = TLASpec(name: "SiblingOperators", variables: [], actions: [], invariants: [
            .init(name: "Check", body: .and(local, local))
        ])
        let rendered = try specification.compile().render().tlaBundle.tla
        #expect(rendered.contains("Check == ((LET item == TRUE\nIN item) /\\ (LET item == TRUE\nIN item))"))
    }

    @Test("Nested checked views render their operands once without capturing source names")
    func checkedViewsPreserveOperandOwnership() throws {
        let compilation = try TLASpec(name: "CheckedViews", variables: [
            .init(name: "_checkedValue", initial: .int(1))
        ], actions: [], invariants: []).compile()
        let variable = try #require(compilation.layout.variables.first?.id)
        let renderer = CompiledTLARenderer(moduleName: "CheckedViews", reservedNames: [], layout: compilation.layout,
            bindings: .init(), operators: compilation.semantics.operators,
            actions: compilation.semantics.behavior.actions, functions: [])
        let source = CompiledExpression.stateVariable(variable)
        #expect(try renderer.state(.assertView(source, .integer))
            == "(LET _checkedValue_ == _checkedValue IN CASE _checkedValue_ \\in Int -> _checkedValue_)")
        var nested = CompiledExpression.value(.integer(123456789))
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
                let value = scope.sharedVar(_name: "value", initial: 0)
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
