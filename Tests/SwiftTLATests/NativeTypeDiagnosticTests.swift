import Testing
@testable import SwiftTLA

@Suite struct NativeTypeDiagnosticTests {
    @Test("deep Boolean expressions retain their Boolean type")
    func longBooleanChains() throws {
        let specification = TLASpec(name: "BooleanChains", variables: [], actions: [], invariants: [])
        let checker = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let expression = (0..<1_000).reduce(CompiledStateExpr.value(.boolean(true))) { nested, index in
            switch index % 3 {
            case 0: .not(nested)
            case 1: .and(nested, .value(.boolean(true)))
            default: .or(.value(.boolean(false)), nested)
            }
        }
        #expect(try checker.resolutionScope(expression, expected: .bool).resultType == .bool)
    }

    @Test("deep conditionals preserve branch types without recursive checking")
    func deepConditionals() throws {
        let specification = TLASpec(name: "ConditionalChains", variables: [], actions: [], invariants: [])
        let checker = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let expression = (0..<1_000).reduce(CompiledStateExpr.value(.integer(1))) { nested, index in
            if index.isMultiple(of: 2) {
                .ifThenElse(.value(.boolean(true)), nested, .value(.integer(0)))
            } else {
                .ifThenElse(.value(.boolean(false)), .value(.integer(0)), nested)
            }
        }
        #expect(try checker.resolutionScope(expression, expected: .int).resultType == .int)
        let invalid = CompiledStateExpr.ifThenElse(.value(.boolean(true)),
            .ifThenElse(.value(.integer(1)), .value(.integer(0)), .value(.integer(2))),
            .value(.string("later")))
        do {
            _ = try checker.type(of: invalid, expected: .int)
            Issue.record("A non-Boolean condition must be rejected first")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasSuffix(" <- value <- ifThenElse <- ifThenElse"))
        }
    }

    @Test("mixed Boolean, conditional, and lexical nesting shares one checking worklist")
    func mixedExpressionNesting() throws {
        let specification = TLASpec(name: "MixedNesting", variables: [], actions: [], invariants: [])
        let checker = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let expression = (0..<1_000).reduce(CompiledStateExpr.value(.boolean(true))) { nested, index in
            switch index % 3 {
            case 0: .not(nested)
            case 1: .ifThenElse(.value(.boolean(true)), nested, .value(.boolean(false)))
            default: .letValue(.init(ordinal: index), .value(.integer(index)), nested)
            }
        }
        #expect(try checker.resolutionScope(expression, expected: .bool).resultType == .bool)
    }

    @Test("nested quantifiers retain their domains inside collection constructors")
    func nestedQuantifierDomains() throws {
        let specification = TLASpec(name: "QuantifierNesting", variables: [], actions: [], invariants: [])
        let checker = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let domain = CompiledStateExpr.setLiteral([.value(.integer(1))])
        let predicate = (0..<1_000).reduce(CompiledStateExpr.value(.boolean(true))) { nested, index in
            let binder = BinderID(ordinal: index)
            return index.isMultiple(of: 2) ? .forAll(domain, binder, nested) : .exists(domain, binder, nested)
        }
        let binder = BinderID(ordinal: 1_000)
        let cases: [(CompiledStateExpr, NativeType)] = [
            (predicate, .bool),
            (.setMap(predicate, binder, domain), .set(.bool)),
            (.functionLiteral(domain, binder, predicate), .dictionary(.int, .bool))
        ]
        for (expression, expected) in cases {
            let checked = try checker.resolutionScope(expression, expected: expected)
            #expect(checked.resultType == expected)
            #expect(checked.scope.bindings[BinderID(ordinal: 0)] == .int)
            #expect(checked.scope.bindings[BinderID(ordinal: 999)] == .int)
        }
    }

    @Test("Boolean diagnostics retain the failing branch's ancestry and left-to-right order")
    func booleanBranchDiagnostics() throws {
        let specification = TLASpec(name: "BooleanBranches", variables: [], actions: [], invariants: [])
        let checker = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let first = CompiledStateExpr.and(.not(.value(.integer(1))), .value(.string("later")))
        let second = CompiledStateExpr.and(.or(.value(.boolean(true)), .value(.boolean(false))), .not(.value(.integer(1))))
        for expression in [first, second] {
            do {
                _ = try checker.resolutionScope(expression, expected: .bool)
                Issue.record("A non-Boolean operand must be rejected")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasSuffix(" <- value <- not <- and"))
            }
        }
    }

    @Test("Incomplete inference identifies the missing field type without an internal expression dump")
    func missingCollectionElement() throws {
        let specification = TLASpec(name: "MissingElementType", variables: [
            .init(name: "accumulator", initialization: .expression(
                .recordLiteral(.init(["execution": .tupleLiteral([])]))), origin: .compiler)
        ], actions: [], invariants: [])
        do {
            _ = try NativeResolvedProgram(plan: .init(compilation: specification.compile()))
            Issue.record("An unresolved element type must not reach Swift emission")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unresolvedGeneratedValueShape)
            #expect(diagnostic.path == "nativeMachine.variables.accumulator")
            #expect(diagnostic.actual == "type inference could not determine value.execution.element")
            #expect(!diagnostic.description.contains("BinderID"))
        }
    }

    @Test("Expression failures report the operation without dumping nested payloads")
    func expressionFailureIdentifiesOperation() throws {
        let specification = TLASpec(name: "InvalidOperand", variables: [
            .init(name: "count", initialization: .value(.int(0)), origin: .compiler)
        ], actions: [], invariants: [])
        let inference = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let payload = String(repeating: "private-expression-payload", count: 1_000)
        let expression = CompiledStateExpr.add(.value(.string(payload)), .value(.integer(1)))
        do {
            _ = try inference.resolutionScope(expression, expected: .int)
            Issue.record("String operands must not be accepted as integers")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasSuffix(" <- value <- add"))
            #expect(!diagnostic.description.contains(payload))
            #expect(!diagnostic.description.contains("CompiledStateExpr"))
        }
    }

}
