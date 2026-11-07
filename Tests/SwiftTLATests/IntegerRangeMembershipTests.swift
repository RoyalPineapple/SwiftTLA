import Foundation
import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct IntegerRangeMembershipTests {
    @Test("generated range membership matches independent ascending and empty bounds")
    func matchesIndependentBounds() throws {
        let specification = IntegerRangeMembershipModel.spec
        let compilation = try specification.compile()
        let sourceAction = try #require(try specification.loweredSourceModel().actions.first)
        let action = try #require(compilation.semantics.behavior.actions.first)
        try #require(sourceAction.name == "check")
        try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
            bindings: action.bindings, body: action.body, layout: compilation.layout)
        for mutation in ["candidate read", "lower read", "upper read", "bound order", "range constructor"] {
            var changed = 0
            let body = action.body.map { expression in
                guard expression.operation == .in, expression.children.count == 2 else { return expression }
                let candidate = expression.children[0]
                let domain = expression.children[1]
                guard domain.operation == .integerRange, domain.children.count == 2 else { return expression }
                let lower = domain.children[0], upper = domain.children[1]
                let member: CompiledExpression
                let range: CompiledExpression
                switch mutation {
                case "candidate read": member = lower; range = domain
                case "lower read":
                    member = candidate
                    range = .init(operation: .integerRange, resultType: domain.resultType, children: [upper, upper])
                case "upper read":
                    member = candidate
                    range = .init(operation: .integerRange, resultType: domain.resultType, children: [lower, lower])
                case "bound order":
                    member = candidate
                    range = .init(operation: .integerRange, resultType: domain.resultType, children: [upper, lower])
                default:
                    member = candidate
                    range = .init(operation: .setLiteral, resultType: domain.resultType, children: [lower, upper])
                }
                changed += 1
                return .init(operation: expression.operation, resultType: expression.resultType,
                    children: [member, range])
            }
            try #require(changed == 1)
            do {
                try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
                    bindings: action.bindings, body: body, layout: compilation.layout)
                Issue.record("Range \(mutation) escaped normalized-source verification")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "actions.\(sourceAction.name).compiledAssignments")
            }
        }
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let checkedAction = try #require(program.behavior.actions.first)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "IntegerRangeMembershipModel", program: program))
        let members = try emitter.machineMembers()
        let visitor = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(checkedAction.id.ordinal)"
        })
        let writes = try emitter.actionFunctions(checkedAction.body).writes
        try verifyGeneratedActionWriteOutput(visitor, action: checkedAction.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let output = try program.renderModule()
        guard case .define(_, let checkedQuery, _) = checkedAction.body else {
            Issue.record("The checked membership lost its compiled value binding")
            return
        }
        let lowerBinder = try #require(program.layout.parameters.first { $0.reference.name == "lower" }).binder
        let upperBinder = try #require(program.layout.parameters.first { $0.reference.name == "upper" }).binder
        let valueBinder = try #require(program.layout.parameters.first { $0.reference.name == "value" }).binder
        let emittedAction = try #require(output.renderedActions.first { $0.sourceName == sourceAction.name })
        let header = "\(emittedAction.emittedBaseName) == "
        let declaration = try #require(output.renderedModuleSource.components(separatedBy: "\n")
            .first { $0.hasPrefix(header) })
        let actualBody = String(declaration.dropFirst(header.count))
        try StraightLineRenderedActionCheck.verifyDeclaration(checkedAction,
            named: emittedAction.emittedBaseName, body: actualBody,
            module: output.renderedModuleSource, layout: program.layout,
            binders: program.binderNames, failureDeclarations: output.evaluationFailureDeclarations)
        let bounds = "let bounds = (configuration.`lower`, configuration.`upper`)"
        for (mutation, swiftBefore, swiftAfter, formalBefore, formalAfter) in [
            ("candidate read", "let candidate = configuration.`value`", "let candidate = configuration.`lower`",
             "value \\in lower..upper", "lower \\in lower..upper"),
            ("lower read", bounds, "let bounds = (configuration.`upper`, configuration.`upper`)",
             "lower..upper", "upper..upper"),
            ("upper read", bounds, "let bounds = (configuration.`lower`, configuration.`lower`)",
             "lower..upper", "lower..lower"),
            ("bound order", bounds, "let bounds = (configuration.`upper`, configuration.`lower`)",
             "lower..upper", "upper..lower"),
            ("range constructor", "bounds.0 <= candidate && candidate <= bounds.1",
             "bounds.0 == candidate || candidate == bounds.1", "lower..upper", "{lower, upper}"),
        ] {
            try #require(visitor.description.components(separatedBy: swiftBefore).count == 2)
            let changedSwift = visitor.description.replacingOccurrences(of: swiftBefore, with: swiftAfter)
            let mutant = try #require(Parser.parse(source: changedSwift)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(mutant, action: checkedAction.body,
                    program: program, stateFields: emitter.stateMemberNames, parts: writes)
                Issue.record("Range emitted Swift \(mutation) escaped output verification")
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
                Issue.record("Range emitted TLA \(mutation) escaped output verification")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "tla.action.scalarAssignments")
            }
        }
        let large = try #require(program.behavior.actions.first {
            program.layout.actions[$0.id.ordinal].declaration.name == "large"
        })
        let largeVisitor = try #require(members.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(large.id.ordinal)"
        })
        let largeWrites = try emitter.actionFunctions(large.body).writes
        try verifyGeneratedActionWriteOutput(largeVisitor, action: large.body,
            program: program, stateFields: emitter.stateMemberNames, parts: largeWrites)
        let boundTuple = "let bounds = (0, 9223372036854775807)"
        let membership = "return { candidate in bounds.0 <= candidate && candidate <= bounds.1 }"
        try #require(largeVisitor.description.components(separatedBy: boundTuple).count == 2)
        try #require(largeVisitor.description.components(separatedBy: membership).count == 2)
        let widthGuard = largeVisitor.description.replacingOccurrences(of: boundTuple,
            with: "let bounds = try SwiftTLA._NativeMachineOperations.integerRangeBounds(0, 9223372036854775807)")
            .replacingOccurrences(of: membership, with: "return { candidate in bounds?.contains(candidate) ?? false }")
        let guardedQuery = try #require(Parser.parse(source: widthGuard)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verifyGeneratedActionWriteOutput(guardedQuery, action: large.body,
                program: program, stateFields: emitter.stateMemberNames, parts: largeWrites)
            Issue.record("Range emitted Swift enumeration budget escaped output verification")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
        for lower in -3...3 {
            for upper in -3...3 {
                for value in -4...4 {
                    var machine = try IntegerRangeMembershipModel.makeMachine(
                        configuration: .init(lower: lower, upper: upper, value: value))
                    #expect(try machine.send(.check).after.result == (lower <= value && value <= upper))
                    let bindings = CompiledBindings().binding(.integer(lower), to: lowerBinder)
                        .binding(.integer(upper), to: upperBinder).binding(.integer(value), to: valueBinder)
                    let evaluator = CompiledEvaluator(variableValues: [:], operators: compilation.semantics.operators,
                        functions: program.functions, bindings: bindings)
                    #expect(try evaluator.evaluate(checkedQuery) == .boolean(lower <= value && value <= upper))
                }
            }
        }
    }

    @Test("generated membership accepts a logical member beyond the enumeration width budget")
    func checksLargeRangeWithoutEnumeration() throws {
        var machine = try IntegerRangeMembershipModel.makeMachine(configuration: .init(lower: 0, upper: 0, value: 4))
        #expect(try machine.send(.large).after.result)
        let compilation = try IntegerRangeMembershipModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let action = try #require(program.behavior.actions.first {
            program.layout.actions[$0.id.ordinal].declaration.name == "large"
        })
        guard case .define(_, let query, _) = action.body else {
            Issue.record("The wide membership query lost its compiled value binding")
            return
        }
        var bindings = CompiledBindings()
        for parameter in program.layout.parameters {
            bindings = bindings.binding(.integer(parameter.reference.name == "value" ? 4 : 0), to: parameter.binder)
        }
        let evaluator = CompiledEvaluator(variableValues: [:], operators: compilation.semantics.operators,
            functions: program.functions, bindings: bindings)
        #expect(try evaluator.evaluate(query) == .boolean(true))
        try #require(query.operation == .in && query.children.count == 2)
        let range = query.children[1]
        try #require(range.operation == .integerRange && range.children.count == 2)
        let singleton = CompiledExpression(operation: .setLiteral, resultType: .set(.int),
            children: [.init(operation: .value(.integer(4)), resultType: .int, children: [])])
        let division = CompiledExpression(operation: .divide, resultType: .int, children: [
            .init(operation: .value(.integer(1)), resultType: .int, children: []),
            .init(operation: .value(.integer(0)), resultType: .int, children: []),
        ])
        let failed = CompiledExpression(operation: .setLiteral, resultType: .set(.int), children: [division])
        let condition = CompiledExpression(operation: .value(.boolean(true)), resultType: .bool, children: [])
        for (domain, expected) in [
            (CompiledExpression(operation: .union, resultType: .set(.int), children: [range, singleton]), true),
            (.init(operation: .intersection, resultType: .set(.int), children: [range, singleton]), true),
            (.init(operation: .setDifference, resultType: .set(.int), children: [range, singleton]), false),
            (.init(operation: .ifThenElse, resultType: .set(.int), children: [condition, range, failed]), true),
            (.init(operation: .ifThenElse, resultType: .set(.int), children: [
                .init(operation: .value(.boolean(false)), resultType: .bool, children: []), failed, range]), true),
            (.init(operation: .setDifference, resultType: .set(.int), children: [
                .init(operation: .integerSet, resultType: .set(.int), children: []), range]), false),
        ] {
            let composed = CompiledExpression(operation: .in, resultType: .bool,
                children: [query.children[0], domain])
            #expect(try evaluator.evaluate(composed) == .boolean(expected))
        }
        let nestedLower = CompiledExpression(operation: .ifThenElse, resultType: .int,
            children: [query, range.children[0], range.children[0]])
        let nestedRange = CompiledExpression(operation: .integerRange, resultType: .set(.int),
            children: [nestedLower, range.children[1]])
        let nestedDomain = CompiledExpression(operation: .union, resultType: .set(.int),
            children: [singleton, nestedRange])
        #expect(try evaluator.evaluate(.init(operation: .in, resultType: .bool,
            children: [query.children[0], nestedDomain])) == .boolean(true))
    }

    @Test("range membership preserves child failures independently of enumeration width")
    func preservesFailures() throws {
        var machine = try IntegerRangeMembershipModel.makeMachine(configuration: .init(lower: 0, upper: 0, value: 0))
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.overflow)
        }
        #expect(machine.snapshot == before)
        for action in [IntegerRangeMembershipModel.Action.candidateFailure, .lowerFailure, .upperFailure, .unionFailure] {
            #expect(throws: NativeMachineEvaluationError.divisionByZero) { try machine.send(action) }
            #expect(machine.snapshot == before)
        }
        let compilation = try IntegerRangeMembershipModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let zero = try #require(program.layout.variables.first { $0.declaration.name == "zero" }).id
        var bindings = CompiledBindings()
        for parameter in program.layout.parameters {
            bindings = bindings.binding(.integer(0), to: parameter.binder)
        }
        let evaluator = CompiledEvaluator(variableValues: [zero: .integer(0)],
            operators: compilation.semantics.operators, functions: program.functions, bindings: bindings)
        let output = try program.renderModule()
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "IntegerRangeMembershipModel", program: program))
        let emittedMembers = try emitter.machineMembers()
        let aggregate = try #require(output.evaluationFailureDeclarations.first {
            $0.hasPrefix("__SwiftTLAEvaluationOK ==")
        })
        #expect(output.configuration.intrinsicInvariants.contains("__SwiftTLAEvaluationOK"))
        let failureRenderer = CompiledTLARenderer(moduleName: program.moduleName, reservedNames: [],
            layout: program.layout, bindings: .init(binders: program.binderNames),
            operators: compilation.semantics.operators,
            actions: program.behavior.actions, functions: program.functions)
        func verifyFailureOutput(_ module: String, declarations: [String]) throws {
            try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
                module: module, failureDeclarations: declarations,
                evaluationInvariant: "__SwiftTLAEvaluationOK", configuration: output.configuration,
                renderer: failureRenderer)
        }
        try verifyFailureOutput(output.renderedModuleSource, declarations: output.evaluationFailureDeclarations)
        for name in ["overflow", "candidateFailure", "lowerFailure", "upperFailure", "unionFailure"] {
            let action = try #require(program.behavior.actions.first {
                program.layout.actions[$0.id.ordinal].declaration.name == name
            })
            guard case .define(_, let query, _) = action.body else {
                Issue.record("The compiled \(name) membership lost its value binding")
                continue
            }
            #expect(throws: EvalError.divisionByZero, "Compiled membership must retain \(name)'s child failure") {
                try evaluator.evaluate(query)
            }
            let division = "__SwiftTLADivisionByZeroFailure\(action.id.ordinal)"
            let failure = "__SwiftTLAAnyEvaluationFailure\(action.id.ordinal)"
            #expect(output.evaluationFailureDeclarations.contains {
                $0.hasPrefix("\(division) ==") && output.renderedModuleSource.contains($0)
            }, "The emitted failure protocol must retain \(name)'s division failure")
            #expect(output.evaluationFailureDeclarations.contains {
                $0.hasPrefix("\(failure) ==") && output.renderedModuleSource.contains($0)
            }, "The emitted failure protocol must retain \(name)'s aggregate")
            #expect(aggregate.contains("~(\(failure))"), "The checking invariant must cover \(name)")

            let visitor = try #require(emittedMembers.first {
                $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates\(action.id.ordinal)"
            })
            let writes = try emitter.actionFunctions(action.body).writes
            try verifyGeneratedActionWriteOutput(visitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: writes)
            let nativeDivision = "SwiftTLA._NativeMachineOperations.divide(_arithmetic1, _arithmetic0)"
            try #require(visitor.description.components(separatedBy: nativeDivision).count == 2)
            let changedSwift = visitor.description.replacingOccurrences(of: nativeDivision,
                with: "SwiftTLA._NativeMachineOperations.divide(0, _arithmetic0)")
            let changedVisitor = try #require(Parser.parse(source: changedSwift)
                .statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(changedVisitor, action: action.body,
                    program: program, stateFields: emitter.stateMemberNames, parts: writes)
                Issue.record("Fallible range emitted Swift dividend escaped output verification: \(name)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.binding."))
            }

            let emitted = try #require(output.renderedActions.first { $0.sourceName == name })
            let header = "\(emitted.emittedBaseName) == "
            let declaration = try #require(output.renderedModuleSource.components(separatedBy: "\n")
                .first { $0.hasPrefix(header) })
            let body = String(declaration.dropFirst(header.count))
            try StraightLineRenderedActionCheck.verifyDeclaration(action,
                named: emitted.emittedBaseName, body: body, module: output.renderedModuleSource,
                layout: program.layout, binders: program.binderNames,
                failureDeclarations: output.evaluationFailureDeclarations)
            for (label, before, after) in [
                ("dividend", " == 1 IN (LET ", " == 2 IN (LET "),
                ("definedness", "IF zero # 0 THEN", "IF TRUE THEN"),
            ] {
                try #require(body.components(separatedBy: before).count == 2)
                let changed = body.replacingOccurrences(of: before, with: after)
                let changedModule = output.renderedModuleSource.replacingOccurrences(
                    of: declaration, with: header + changed)
                try #require(changedModule != output.renderedModuleSource)
                do {
                    try StraightLineRenderedActionCheck.verifyDeclaration(action,
                        named: emitted.emittedBaseName, body: changed, module: changedModule,
                        layout: program.layout, binders: program.binderNames,
                        failureDeclarations: output.evaluationFailureDeclarations)
                    Issue.record("Fallible range emitted TLA \(label) escaped output verification: \(name)")
                } catch let diagnostic as CompilationDiagnostic {
                    #expect(diagnostic.path == "tla.action.scalarAssignments")
                }
            }
            for (label, base, wrongValue) in [
                ("divisor", "__SwiftTLADivisionByZeroDivisor\(action.id.ordinal)", "1"),
                ("aggregate", failure, "FALSE"),
            ] {
                let original = try #require(output.evaluationFailureDeclarations.first {
                    $0.hasPrefix(base + " == ")
                })
                let changed = base + " == " + wrongValue
                try #require(changed != original)
                try #require(output.renderedModuleSource.components(separatedBy: original).count == 2)
                let changedModule = output.renderedModuleSource.replacingOccurrences(of: original, with: changed)
                do {
                    try verifyFailureOutput(changedModule,
                        declarations: output.evaluationFailureDeclarations.map { $0 == original ? changed : $0 })
                    Issue.record("Fallible range emitted TLA failure \(label) escaped output verification: \(name)")
                } catch let diagnostic as CompilationDiagnostic {
                    #expect(diagnostic.path == "tla.evaluationSelection")
                }
            }
            if name == "overflow" {
                var nestedDivisionCount = 0
                let nested = action.body.map { expression in
                    guard expression.operation == .in, expression.children.count == 2,
                          expression.children[0].operation == .divide
                            || expression.children[0].operation == .integerDivide else { return expression }
                    nestedDivisionCount += 1
                    let candidate = expression.children[0]
                    let divided = CompiledExpression(operation: candidate.operation, resultType: .int,
                        children: [candidate, candidate])
                    return CompiledExpression(operation: .in, resultType: .bool,
                        children: [divided, expression.children[1]])
                }
                try #require(nestedDivisionCount == 1)
                let namespace = program.moduleName + "_Scoped"
                let occupied: Set<String> = ["__\(namespace)_dividend0", "__\(namespace)_divisor1"]
                let renderer = CompiledTLARenderer(moduleName: namespace, reservedNames: occupied,
                    layout: program.layout, bindings: .init(binders: program.binderNames),
                    operators: compilation.semantics.operators,
                    actions: program.behavior.actions, functions: program.functions)
                // The derived nested tree checks binder numbering, not accepted-source lowering.
                for value in [action.body, nested] {
                    let emitted = try renderer.action(value)
                    try StraightLineRenderedActionCheck.verify(value, rendered: emitted,
                        layout: program.layout, binders: program.binderNames,
                        moduleName: namespace, reservedNames: occupied, required: true)
                    let captured = emitted.replacingOccurrences(of: "__\(namespace)_dividend0_", with: "zero")
                    try #require(captured != emitted)
                    do {
                        try StraightLineRenderedActionCheck.verify(value, rendered: captured,
                            layout: program.layout, binders: program.binderNames,
                            moduleName: namespace, reservedNames: occupied, required: true)
                        Issue.record("Fallible range temporary captured an authored state read")
                    } catch let diagnostic as CompilationDiagnostic {
                        #expect(diagnostic.path == "tla.action.scalarAssignments")
                    }
                }
            }
        }
    }

    @Test("checked range bounds retain integer-limit and empty-range semantics")
    func integerBoundaries() throws {
        #expect(try _NativeMachineOperations.integerRangeBounds(Int.max, Int.min) == nil)
        #expect(try _NativeMachineOperations.integerRangeBounds(Int.min, Int.min + 1) == Int.min...(Int.min + 1))
        #expect(try _NativeMachineOperations.integerRangeBounds(Int.max - 1, Int.max) == (Int.max - 1)...Int.max)
        for lower in [Int.min, 0] {
            #expect(throws: NativeMachineEvaluationError.collectionCardinalityOverflow(.integerRange, operands: [lower, Int.max])) {
                try _NativeMachineOperations.integerRangeBounds(lower, Int.max)
            }
        }
    }
}
