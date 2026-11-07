import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct IntegerRangeDomainEqualityTests {
    private func query(named name: String, program: CompiledProgram) throws -> CompiledExpression {
        let action = try #require(program.behavior.actions.first {
            program.layout.actions[$0.id.ordinal].declaration.name == name
        })
        var queries: [CompiledExpression] = []
        _ = action.body.map { value in
            if value.operation == .equal, value.children.count == 2,
               value.children.contains(where: { $0.operation == .domain }),
               value.children.contains(where: { $0.operation == .integerRange }) {
                queries.append(value)
            }
            return value
        }
        try #require(queries.count == 1)
        return queries[0]
    }

    private func evaluator(program: CompiledProgram, members: Set<Int>, lower: Int,
                           upper: Int) throws -> CompiledEvaluator {
        let values = try #require(program.layout.variables.first { $0.declaration.name == "values" })
        let zero = try #require(program.layout.variables.first { $0.declaration.name == "zero" })
        var bindings = CompiledBindings()
        let parameters: [(String, CompiledValue)] = [
            ("members", .set(Set(members.map(CompiledValue.integer)))),
            ("lower", .integer(lower)), ("upper", .integer(upper)),
        ]
        for (name, value) in parameters {
            let parameter = try #require(program.layout.parameters.first { $0.reference.name == name })
            bindings = bindings.binding(value, to: parameter.binder)
        }
        return CompiledEvaluator(variableValues: [
            values.id: .function(Dictionary(uniqueKeysWithValues: members.map {
                (CompiledValue.integer($0), CompiledValue.integer(0))
            })), zero.id: .integer(0),
        ], operators: .init(), functions: program.functions, bindings: bindings)
    }

    @Test("domain equality agrees with complete, sparse, and empty integer ranges")
    func agreesWithEnumeration() throws {
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(
            in: IntegerRangeDomainEqualityModel.spec.compile()))
        let queries = try ["check", "reversed"].map { try query(named: $0, program: program) }
        let populations: [Set<Int>] = [[], [1, 2], [1, 3]]
        for members in populations {
            for (lower, upper) in [(1, 2), (2, 1), (1, 3), (-1, 1)] {
                let expected = members == (lower <= upper ? Set(lower...upper) : [])
                let configuration = try IntegerRangeDomainEqualityModel.Configuration(
                    members: members, lower: lower, upper: upper)
                var machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: configuration)
                #expect(try machine.send(.check).after.result == expected)
                machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: configuration)
                #expect(try machine.send(.reversed).after.result == expected)
                let compiled = try evaluator(program: program, members: members, lower: lower, upper: upper)
                for query in queries {
                    #expect(try compiled.evaluate(query) == .boolean(expected))
                }
            }
        }
    }

    @Test("domain equality checks large range bounds without enumeration")
    func largeRangeDoesNotEnumerate() throws {
        let specification = IntegerRangeDomainEqualityModel.spec
        let compilation = try specification.compile()
        let sourceAction = try #require(try specification.loweredSourceModel().actions.first { $0.name == "check" })
        let untyped = try #require(compilation.semantics.behavior.actions.first {
            compilation.layout.actions[$0.id.ordinal].declaration.name == "check"
        })
        try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
            bindings: untyped.bindings, body: untyped.body, layout: compilation.layout)
        for label in ["boundOrder", "rangeConstructor", "operator"] {
            var changed = 0
            let body = untyped.body.map { value in
                guard value.operation == .equal, value.children.count == 2,
                      value.children[0].operation == .domain,
                      value.children[1].operation == .integerRange else { return value }
                let range = value.children[1]
                changed += 1
                if label == "operator" {
                    return .init(operation: .notEqual, resultType: value.resultType, children: value.children)
                }
                let replacement = CompiledExpression(
                    operation: label == "boundOrder" ? .integerRange : .setLiteral,
                    resultType: range.resultType,
                    children: label == "boundOrder" ? Array(range.children.reversed()) : range.children)
                return .init(operation: .equal, resultType: value.resultType,
                    children: [value.children[0], replacement])
            }
            try #require(changed == 1)
            do {
                try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
                    bindings: untyped.bindings, body: body, layout: compilation.layout)
                Issue.record("Domain equality source corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "actions.check.compiledAssignments")
            }
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let checkedAction = try #require(program.behavior.actions.first {
            program.layout.actions[$0.id.ordinal].declaration.name == "check"
        })
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "IntegerRangeDomainEqualityModel", program: program))
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(checkedAction.id.ordinal)"
        })
        let writes = try emitter.actionFunctions(checkedAction.body).writes
        try verifyGeneratedActionWriteOutput(visitor, action: checkedAction.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let output = try program.renderModule()
        let emittedAction = try #require(output.renderedActions.first { $0.sourceName == "check" })
        let header = "\(emittedAction.emittedBaseName) == "
        let declaration = try #require(output.renderedModuleSource.components(separatedBy: "\n")
            .first { $0.hasPrefix(header) })
        let actualBody = String(declaration.dropFirst(header.count))
        try StraightLineRenderedActionCheck.verifyDeclaration(checkedAction,
            named: emittedAction.emittedBaseName, body: actualBody,
            module: output.renderedModuleSource, layout: program.layout,
            binders: program.binderNames, failureDeclarations: output.evaluationFailureDeclarations)
        for (label, swiftBefore, swiftAfter, formalBefore, formalAfter) in [
            ("boundOrder", "let _domainBounds = (configuration.`lower`, configuration.`upper`)",
             "let _domainBounds = (configuration.`upper`, configuration.`lower`)",
             "lower..upper", "upper..lower"),
            ("rangeConstructor", "_domainLast.partialValue == _domainBounds.1", "true",
             "lower..upper", "{lower, upper}"),
            ("domainConstructor", "_domainFunction.keys.allSatisfy { _domainBounds.0 <= $0 && $0 <= _domainBounds.1 }", "true",
             "DOMAIN values", "{}"),
        ] {
            try #require(visitor.description.components(separatedBy: swiftBefore).count == 2)
            let changedSwift = visitor.description.replacingOccurrences(of: swiftBefore, with: swiftAfter)
            let corrupted = try #require(Parser.parse(source: changedSwift)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(corrupted, action: checkedAction.body,
                    program: program, stateFields: emitter.stateMemberNames, parts: writes)
                Issue.record("Domain equality Swift corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.binding."))
            }
            try #require(actualBody.components(separatedBy: formalBefore).count == 2)
            let changedFormal = actualBody.replacingOccurrences(of: formalBefore, with: formalAfter)
            let changedModule = output.renderedModuleSource.replacingOccurrences(
                of: declaration, with: header + changedFormal)
            try #require(changedModule != output.renderedModuleSource)
            do {
                try StraightLineRenderedActionCheck.verifyDeclaration(checkedAction,
                    named: emittedAction.emittedBaseName, body: changedFormal,
                    module: changedModule, layout: program.layout, binders: program.binderNames,
                    failureDeclarations: output.evaluationFailureDeclarations)
                Issue.record("Domain equality TLA corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "tla.action.scalarAssignments")
            }
        }
        var machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: .init(
            members: [], lower: 1, upper: 2))
        let before = machine.snapshot
        do {
            #expect(try !machine.send(.large).after.result)
            #expect(machine.state.values.isEmpty)
        } catch {
            Issue.record("Native wide equality reported enumeration capability instead of false: \(error)")
            #expect(machine.snapshot == before)
        }
        let compiled = try evaluator(program: program, members: [], lower: 1, upper: 2)
        let largeQuery = try query(named: "large", program: program)
        do {
            #expect(try compiled.evaluate(largeQuery) == .boolean(false))
        } catch {
            Issue.record("Compiled wide equality reported enumeration capability instead of false: \(error)")
        }
    }

    @Test("domain equality preserves operand failure order")
    func preservesFailureOrder() throws {
        var machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: .init(
            members: [], lower: 1, upper: 2))
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.domainFirstFailure)
        }
        #expect(machine.snapshot == before)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.rangeFirstFailure)
        }
        #expect(machine.snapshot == before)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(
            in: IntegerRangeDomainEqualityModel.spec.compile()))
        let compiled = try evaluator(program: program, members: [], lower: 1, upper: 2)
        for name in ["domainFirstFailure", "rangeFirstFailure"] {
            let value = try query(named: name, program: program)
            #expect(throws: EvalError.divisionByZero) { try compiled.evaluate(value) }
        }
    }
}
