import Foundation
import Testing
@testable import SwiftTLA

@Suite("Compiled specification rendering")
struct CompiledSpecificationRendererTests {
    @Test("Signed division uses a positive formal divisor")
    func rendersSignedDivision() throws {
        let compiled = try TLASpec(name: "SignedDivision", variables: [], actions: [], invariants: []).compile()
        let dividend = BinderID(ordinal: 0)
        let divisor = BinderID(ordinal: 1)
        let renderer = CompiledTLARenderer(moduleName: "SignedDivision", reservedNames: [], layout: compiled.layout,
            bindings: .init(binders: [dividend: "dividend", divisor: "divisor"]),
            operators: compiled.semantics.operators, actions: [], functions: [])
        let proofFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Verification/Semantics/SingleAssignment.tla")
        let proof = try String(contentsOf: proofFile, encoding: .utf8)
        let start = try #require(proof.range(of: "RenderedSignedDivision(dividend, divisor) =="))
        let end = try #require(proof.range(of: "THEOREM SignedDivisionUsesPositiveDivisor =="))
        let provedExpression = proof[start.upperBound..<end.lowerBound]
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for operation in [CompiledOperation.divide, .integerDivide] {
            let expression = CompiledExpression(operation: operation, resultType: .int,
                children: [.value(.integer(5)), .value(.integer(-2))])
            #expect(try renderer.state(expression)
                == "(LET __SignedDivision_dividend0 == 5 IN (LET __SignedDivision_divisor1 == -2 IN (IF __SignedDivision_divisor1 < 0 THEN (-__SignedDivision_dividend0) \\div (-__SignedDivision_divisor1) ELSE __SignedDivision_dividend0 \\div __SignedDivision_divisor1)))")
            let symbolic = CompiledExpression(operation: operation, resultType: .int,
                children: [.boundValue(dividend), .boundValue(divisor)])
            #expect(try renderer.state(symbolic) == provedExpression)
        }
    }

    @Test("Powerset operands retain their grouping inside function domains")
    func groupsPowersetRangeOperand() throws {
        let compiled = try TLASpec(name: "PowersetDomain", variables: [], actions: [], invariants: []).compile()
        let renderer = CompiledTLARenderer(moduleName: "PowersetDomain", reservedNames: [], layout: compiled.layout,
            bindings: .init(), operators: compiled.semantics.operators, actions: [], functions: [])
        let interval = CompiledExpression(operation: .integerRange,
            children: [.value(.integer(1)), .value(.integer(2))])
        let domain = CompiledExpression(operation: .functionSet, children: [interval,
            .init(operation: .powerSet, children: [interval])])
        #expect(try renderer.state(domain) == "[1..2 -> SUBSET (1..2)]")
    }

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
            constraints: [.init(.enabledAction("ready"))]).compile()
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
            (.and, ["left", "right"], "(IF left THEN right ELSE FALSE)"),
            (.or, ["left", "right"], "(IF left THEN TRUE ELSE right)"),
            (.not, ["value"], "(~value)"),
            (.ifThenElse, ["condition", "yes", "no"], "(IF condition THEN yes ELSE no)"),
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
        let compilation = try TLASpec(name: "BooleanComposition", variables: [], actions: [], invariants: []).compile()
        let identifiers = (0..<5).map { BinderID(ordinal: $0) }
        let names = Dictionary(uniqueKeysWithValues: zip(identifiers, ["condition", "guard", "yes", "no", "fallback"]))
        let renderer = CompiledTLARenderer(moduleName: "BooleanComposition", reservedNames: [],
            layout: compilation.layout, bindings: .init(binders: names),
            operators: compilation.semantics.operators, actions: [], functions: [])
        let leaves = identifiers.map { CompiledExpression.boundValue($0) }
        let nested = CompiledExpression(operation: .ifThenElse, children: [
            .init(operation: .and, children: [leaves[0], .init(operation: .not, children: [leaves[1]])]),
            .init(operation: .or, children: [leaves[2], leaves[3]]),
            .init(operation: .not, children: [leaves[4]])
        ])
        #expect(try renderer.state(nested)
            == "(IF (IF condition THEN (~guard) ELSE FALSE) THEN (IF yes THEN TRUE ELSE no) ELSE (~fallback))")
        #expect(throws: CompilationDiagnostic.self) {
            try CompiledOperation.caseExpr(hasOtherwise: false).tlaSyntax(
                operandCount: 3, binderName: { _ in "item" })
        }
    }

    @Test("Selected Boolean branches retain ordered evaluation failures in TLA output")
    func selectedBooleanFailures() throws {
        let compilation = try TLASpec(name: "BooleanFailures", variables: [], actions: [], invariants: []).compile()
        let enabledID = BinderID(ordinal: 0)
        let divisorID = BinderID(ordinal: 1)
        let renderer = CompiledTLARenderer(moduleName: "BooleanFailures", reservedNames: [],
            layout: compilation.layout, bindings: .init(binders: [enabledID: "enabled", divisorID: "divisor"]),
            operators: compilation.semantics.operators, actions: [], functions: [])
        let enabled = CompiledExpression(operation: .boundValue(enabledID), resultType: .bool, children: [])
        let divisor = CompiledExpression(operation: .boundValue(divisorID), resultType: .int, children: [])
        let remainder = CompiledExpression(operation: .modulo, resultType: .int,
            children: [.value(.integer(1)), divisor])
        let fallible = CompiledExpression(operation: .equal, resultType: .bool,
            children: [remainder, .value(.integer(0))])
        let cases: [(CompiledExpression, String, String)] = [
            (.init(operation: .and, children: [enabled, fallible]),
                "(IF enabled THEN divisor # 0 ELSE TRUE)", "(IF enabled THEN divisor > 0 ELSE TRUE)"),
            (.init(operation: .or, children: [enabled, fallible]),
                "(IF enabled THEN TRUE ELSE divisor # 0)", "(IF enabled THEN TRUE ELSE divisor > 0)"),
            (.init(operation: .ifThenElse, children: [enabled, .value(.boolean(true)), fallible]),
                "(IF enabled THEN TRUE ELSE divisor # 0)", "(IF enabled THEN TRUE ELSE divisor > 0)"),
            (.init(operation: .not, children: [fallible]), "divisor # 0", "divisor > 0")
        ]
        for (expression, zeroGuard, positiveGuard) in cases {
            let failures = try renderer.expressionEvaluationFailures(expression)
            guard failures.count == 2 else {
                Issue.record("The branch must retain both modulo failures")
                continue
            }
            guard case .divisionByZero = failures[0].kind,
                  case .negativeModuloDivisor = failures[1].kind else {
                Issue.record("The branch changed the ordered failure identities")
                continue
            }
            #expect(failures.map(\.predicate) == [
                "~(\(zeroGuard))",
                "(IF \(zeroGuard) THEN ~(\(positiveGuard)) ELSE FALSE)"
            ])
            #expect(try renderer.evaluationDefined(expression)
                == "(IF \(zeroGuard) THEN (IF \(positiveGuard) THEN TRUE ELSE FALSE) ELSE FALSE)")
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

    @Test("Direct assignments guard fallible values and report their failures")
    func guardsFallibleDirectAssignment() throws {
        let compilation = try TLASpec(name: "DirectAssignment", variables: [
            .init(name: "result", initial: .int(0))
        ], actions: [], invariants: []).compile()
        let variable = try #require(compilation.layout.variables.first?.id)
        let binder = BinderID(ordinal: 0)
        let renderer = CompiledTLARenderer(moduleName: "DirectAssignment", reservedNames: [],
            layout: compilation.layout, bindings: .init(binders: [binder: "candidate"]),
            operators: compilation.semantics.operators, actions: [], functions: [])
        let empty = CompiledExpression(operation: .value(.set([])), resultType: .set(.int), children: [])
        let yes = CompiledExpression(operation: .value(.boolean(true)), resultType: .bool, children: [])
        let choice = CompiledExpression(operation: .choose(binder), resultType: .int, children: [empty, yes])
        let selected = CompiledActionExpr.assign(variable, choice)
        let selectedAction = try renderer.action(selected)
        #expect(selectedAction.hasPrefix("(IF "))
        #expect(selectedAction.contains(#"\E candidate \in {} : TRUE"#))
        #expect(selectedAction.contains("result' = (LET __DirectAssignment_choiceCandidates"))
        #expect(selectedAction.contains("CHOOSE candidate"))
        #expect(selectedAction.hasSuffix("ELSE FALSE)"))
        #expect(try renderer.choiceFailure(selected) == #"~((\E candidate \in {} : TRUE))"#)

        let specification = TLASpec(name: "DirectAssignmentOutput", variables: [
            .init(name: "result", initial: .int(0))
        ], actions: [
            .init(name: "pick", body: .assign(.named("result"),
                .choose(.setLiteral([.int(1)]), "candidate", .bool(false))))
        ], invariants: [])
        let emitted = try specification.compile().render()
        #expect(emitted.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        #expect(emitted.tlaBundle.tla.contains("pick == (IF "))
        #expect(emitted.tlaBundle.tla.contains("__SwiftTLAChoiceFailure0 =="))

        let zero = CompiledExpression(operation: .value(.integer(0)), resultType: .int, children: [])
        let one = CompiledExpression(operation: .value(.integer(1)), resultType: .int, children: [])
        let quotient = CompiledExpression(operation: .divide, resultType: .int, children: [one, zero])
        let divided = CompiledActionExpr.assign(variable, quotient)
        #expect(try renderer.action(divided).contains("ELSE FALSE"))
        #expect(try renderer.evaluationFailures(divided).contains {
            if case .divisionByZero = $0.kind { true } else { false }
        })
    }

    @Test("Infallible assignments do not emit an evaluation-failure invariant")
    func omitsInfallibleEvaluationCheck() throws {
        let specification = TLASpec(name: "InfallibleAssignment", variables: [
            .init(name: "result", initial: .int(0))
        ], actions: [
            .init(name: "advance", body: .assign(.named("result"), .int(1)))
        ], invariants: [])
        let emitted = try specification.compile().render()
        #expect(emitted.intrinsicInvariantNames.isEmpty)
        #expect(!emitted.tlaBundle.tla.contains("__SwiftTLAAnyEvaluationFailure"))
    }

    @Test("A successful left action exposes a right-hand evaluation failure")
    func reportsFailureAfterConjunctiveAssignment() throws {
        let compilation = try TLASpec(name: "ConjunctiveFailure", variables: [
            .init(name: "result", initial: .int(0))
        ], actions: [], invariants: []).compile()
        let variable = try #require(compilation.layout.variables.first?.id)
        let renderer = CompiledTLARenderer(moduleName: "ConjunctiveFailure", reservedNames: [],
            layout: compilation.layout, bindings: .init(binders: [BinderID(ordinal: 0): "candidate"]),
            operators: compilation.semantics.operators,
            actions: [], functions: [])
        let one = CompiledExpression.value(.integer(1))
        let zero = CompiledExpression.value(.integer(0))
        let quotient = CompiledExpression(operation: .divide, resultType: .int, children: [one, zero])
        let action = CompiledActionExpr.and(.assign(variable, one), .assign(variable, quotient))

        let failures = try renderer.evaluationFailures(action)
        #expect(failures.contains {
            if case .divisionByZero = $0.kind {
                return $0.predicate.contains("ENABLED (result' = 1)")
            }
            return false
        })

        let empty = CompiledExpression.value(.set([]))
        let yes = CompiledExpression.value(.boolean(true))
        let choice = CompiledExpression(operation: .choose(BinderID(ordinal: 0)), resultType: .int,
            children: [empty, yes])
        let chosen = CompiledActionExpr.and(.assign(variable, one), .assign(variable, choice))
        #expect(try renderer.choiceFailure(chosen)?.contains("ENABLED (result' = 1)") == true)
    }

    @Test("An undefined existential domain disables its TLA action and reports the failure")
    func guardsUndefinedChoiceDomain() throws {
        let compilation = try TLASpec(name: "UndefinedChoiceDomain", variables: [
            .init(name: "result", initial: .int(0))
        ], actions: [], invariants: []).compile()
        let variable = try #require(compilation.layout.variables.first?.id)
        let binder = BinderID(ordinal: 0)
        let renderer = CompiledTLARenderer(moduleName: "UndefinedChoiceDomain", reservedNames: [],
            layout: compilation.layout, bindings: .init(binders: [binder: "candidate"]),
            operators: compilation.semantics.operators, actions: [], functions: [])
        let quotient = CompiledExpression(operation: .divide, resultType: .int,
            children: [.value(.integer(1)), .value(.integer(0))])
        let domain = CompiledExpression(operation: .setLiteral, resultType: .set(.int), children: [quotient])
        let action = CompiledActionExpr.existsAction(binder, domain,
            .assign(variable, .boundValue(binder)))

        let rendered = try renderer.action(action)
        #expect(rendered.hasPrefix("(IF "))
        #expect(rendered.contains("THEN (\\E candidate \\in"))
        #expect(rendered.hasSuffix("ELSE FALSE)"))
        #expect(try renderer.evaluationFailures(action).contains {
            if case .divisionByZero = $0.kind { true } else { false }
        })
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
        #expect(rendered.contains("Check == (IF (LET item == TRUE\nIN item) THEN (LET item == TRUE\nIN item) ELSE FALSE)"))
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
        #expect(bundle.provenance == directBundle.provenance)
        guard case let .compiled(identity, _, _) = bundle.provenance else {
            Issue.record("A compiled authored PlusCal bundle lost its provenance.")
            return
        }
        #expect(identity == compilation.identity)

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
