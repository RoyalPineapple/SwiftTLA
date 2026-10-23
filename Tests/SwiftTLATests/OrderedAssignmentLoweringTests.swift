import Foundation
import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

@Suite("Ordered assignment lowering")
struct OrderedAssignmentLoweringTests {
    private enum Symbol: Equatable {
        case initial(String)
        case literal(TLAValue)
    }

    private enum InvalidShape: Error {
        case source
        case lowered
        case rendered
    }

    private func value(
        _ expression: StateExpr, state: [String: Symbol], bindings: [String: Symbol] = [:]
    ) throws -> Symbol {
        switch expression {
        case .variable(let name):
            if let bound = bindings[name] { return bound }
            guard let current = state[name] else { throw InvalidShape.source }
            return current
        case .value(let literal): return .literal(literal)
        default: throw InvalidShape.source
        }
    }

    private func initial(_ roots: [String]) -> [String: Symbol] {
        Dictionary(uniqueKeysWithValues: roots.map { ($0, .initial($0)) })
    }

    private func sourceResult(
        _ statements: [AlgorithmStatementModel], roots: [String]
    ) throws -> [String: Symbol] {
        var state = initial(roots)
        for statement in statements {
            guard case .set(let target, let expression) = statement,
                  case .root(let root) = target, state[root] != nil else { throw InvalidShape.source }
            state[root] = try value(expression, state: state)
        }
        return state
    }

    private func loweredResult(_ action: ActionExpr, roots: [String]) throws -> [String: Symbol] {
        let original = initial(roots)
        var writes: [String: Symbol] = [:]
        func visit(_ action: ActionExpr, bindings: [String: Symbol]) throws {
            switch action {
            case .define(let name, let expression, let body):
                guard bindings[name] == nil, original[name] == nil else { throw InvalidShape.lowered }
                var nested = bindings
                nested[name] = try value(expression, state: original, bindings: bindings)
                try visit(body, bindings: nested)
            case .and(let left, let right):
                try visit(left, bindings: bindings)
                try visit(right, bindings: bindings)
            case .guard_(.value(.bool(true))): break
            case .assign(.named(let root), let expression):
                guard original[root] != nil, writes[root] == nil else { throw InvalidShape.lowered }
                writes[root] = try value(expression, state: original, bindings: bindings)
            case .unchanged(.named(let root)):
                guard let previous = original[root], writes[root] == nil else { throw InvalidShape.lowered }
                writes[root] = previous
            default: throw InvalidShape.lowered
            }
        }
        try visit(action, bindings: [:])
        guard writes.count == original.count else { throw InvalidShape.lowered }
        return writes
    }

    private func lower(_ statements: [AlgorithmStatementModel], roots: [String]) throws -> ActionExpr {
        let step = AtomicStep(model: .init(label: .init(name: "advance"), statements: statements))
        let action = try AlgorithmLowerer.lowerAtomicStep(step).action
        return ActionNormalization.complete(action, variables: roots.map { NamedVar(name: $0, initial: .int(0)) })
    }

    private func compiledResult(
        _ action: CompiledActionExpr, program: CompiledProgram
    ) throws -> [String: Symbol] {
        let names = Dictionary(uniqueKeysWithValues: program.layout.variables.map { ($0.id, $0.declaration.name) })
        let original = initial(program.layout.variables.map(\.declaration.name))
        var writes: [String: Symbol] = [:]
        func value(_ expression: CompiledExpression, bindings: [BinderID: Symbol]) throws -> Symbol {
            guard expression.children.isEmpty else { throw InvalidShape.lowered }
            switch expression.operation {
            case .stateVariable(let id):
                guard let name = names[id], let current = original[name] else { throw InvalidShape.lowered }
                return current
            case .boundValue(let id):
                guard let bound = bindings[id] else { throw InvalidShape.lowered }
                return bound
            case .value(.integer(let number)): return .literal(.int(number))
            case .value(.boolean(let boolean)): return .literal(.bool(boolean))
            default: throw InvalidShape.lowered
            }
        }
        func visit(_ action: CompiledActionExpr, bindings: [BinderID: Symbol]) throws {
            switch action {
            case .define(let id, let expression, let body):
                guard bindings[id] == nil else { throw InvalidShape.lowered }
                var nested = bindings
                nested[id] = try value(expression, bindings: bindings)
                try visit(body, bindings: nested)
            case .and(let left, let right):
                try visit(left, bindings: bindings)
                try visit(right, bindings: bindings)
            case .guard_(let predicate):
                guard try value(predicate, bindings: bindings) == .literal(.bool(true)) else {
                    throw InvalidShape.lowered
                }
            case .assign(let id, let expression):
                guard let name = names[id], writes[name] == nil else { throw InvalidShape.lowered }
                writes[name] = try value(expression, bindings: bindings)
            case .unchanged(let id):
                guard let name = names[id], let previous = original[name], writes[name] == nil else {
                    throw InvalidShape.lowered
                }
                writes[name] = previous
            default: throw InvalidShape.lowered
            }
        }
        try visit(action, bindings: [:])
        guard writes.count == original.count else { throw InvalidShape.lowered }
        return writes
    }

    private func renderedResult(_ declaration: String, roots: [String]) throws -> [String: Symbol] {
        let pattern = try NSRegularExpression(pattern: #"\s+|==|/\\|[()]|=|[A-Za-z_][A-Za-z0-9_]*'?|-?[0-9]+"#)
        let text = declaration as NSString
        var tokens: [String] = []
        var offset = 0
        while offset < text.length {
            guard let match = pattern.firstMatch(in: declaration, range: NSRange(location: offset, length: text.length - offset)),
                  match.range.location == offset else { throw InvalidShape.rendered }
            let token = text.substring(with: match.range)
            if !token.first!.isWhitespace { tokens.append(token) }
            offset = match.range.upperBound
        }

        let original = initial(roots)
        var position = 0
        func take(_ expected: String) throws {
            guard tokens.indices.contains(position), tokens[position] == expected else { throw InvalidShape.rendered }
            position += 1
        }
        func atom(_ bindings: [String: Symbol]) throws -> Symbol {
            guard tokens.indices.contains(position) else { throw InvalidShape.rendered }
            let token = tokens[position]
            position += 1
            if let number = Int(token) { return .literal(.int(number)) }
            if token == "TRUE" { return .literal(.bool(true)) }
            if token == "FALSE" { return .literal(.bool(false)) }
            if let bound = bindings[token] { return bound }
            guard let value = original[token] else { throw InvalidShape.rendered }
            return value
        }
        func action(_ bindings: [String: Symbol]) throws -> [String: Symbol] {
            if tokens.indices.contains(position), tokens[position] == "(" {
                try take("(")
                if tokens.indices.contains(position), tokens[position] == "LET" {
                    try take("LET")
                    guard tokens.indices.contains(position) else { throw InvalidShape.rendered }
                    let name = tokens[position]
                    position += 1
                    guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
                          original[name] == nil, bindings[name] == nil else { throw InvalidShape.rendered }
                    try take("==")
                    let value = try atom(bindings)
                    try take("IN")
                    var nested = bindings
                    nested[name] = value
                    let writes = try action(nested)
                    try take(")")
                    return writes
                }
                let left = try action(bindings)
                try take("/\\")
                let right = try action(bindings)
                try take(")")
                return try left.merging(right) { _, _ in throw InvalidShape.rendered }
            }
            guard tokens.indices.contains(position) else { throw InvalidShape.rendered }
            if tokens[position] == "TRUE" {
                position += 1
                return [:]
            }
            if tokens[position] == "UNCHANGED" {
                position += 1
                guard tokens.indices.contains(position), let previous = original[tokens[position]] else {
                    throw InvalidShape.rendered
                }
                let root = tokens[position]
                position += 1
                return [root: previous]
            }
            let target = tokens[position]
            position += 1
            guard target.hasSuffix("'"), original[String(target.dropLast())] != nil else {
                throw InvalidShape.rendered
            }
            try take("=")
            return [String(target.dropLast()): try atom(bindings)]
        }
        let writes = try action([:])
        guard position == tokens.count, writes.count == original.count else { throw InvalidShape.rendered }
        return writes
    }

    @Test("Straight-line copy and literal assignments read the preceding complete state")
    func straightLineAssignmentsPreserveOrderedState() throws {
        let roots = ["x", "y", "z"]
        let statements: [AlgorithmStatementModel] = [
            .set(target: .root("x"), value: .variable("y")),
            .set(target: .root("y"), value: .variable("x")),
            .set(target: .root("x"), value: .value(.int(3))),
            .set(target: .root("z"), value: .variable("x")),
        ]
        for prefix in 0...statements.count {
            let source = Array(statements.prefix(prefix))
            let expected = try sourceResult(source, roots: roots)
            #expect(try loweredResult(lower(source, roots: roots), roots: roots) == expected)

            var specification = TLASpec(name: "OrderedAssignmentPrefix", variables: roots.map {
                NamedVar(name: $0, initial: .int(0))
            }, actions: [], invariants: [])
            specification.sourceAtomicSteps = [AtomicStep(model: .init(
                label: .init(name: "advance"), statements: source))]
            let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
            let compiled = try #require(program.behavior.actions.first)
            #expect(try compiledResult(compiled.body, program: program) == expected)
            var emitter = NativeSwiftEmitter(model: try MacroCompilation(
                typeName: "OrderedAssignmentPrefix", program: program))
            _ = try emitter.machineMembers()

            let module = try program.renderModule().renderedModuleSource
            let header = "advance == "
            let declarations = module.split(separator: "\n").filter { $0.hasPrefix(header) }
            let declaration = try #require(declarations.count == 1 ? declarations[0].dropFirst(header.count) : nil)
            try StraightLineRenderedActionCheck.verify(compiled.body, rendered: String(declaration),
                layout: program.layout, binders: program.binderNames)
            #expect(try renderedResult(String(declaration), roots: roots) == expected)
        }
    }

    @Test("Boolean literals and copies keep their complete TLA+ assignment meaning")
    func booleanAssignmentsPreserveOrderedState() throws {
        let roots = ["flag", "copy"]
        let statements: [AlgorithmStatementModel] = [
            .set(target: .root("flag"), value: .value(.bool(true))),
            .set(target: .root("copy"), value: .variable("flag")),
        ]
        var specification = TLASpec(name: "OrderedBooleanAssignments", variables: roots.map {
            NamedVar(name: $0, initial: .bool(false))
        }, actions: [], invariants: [])
        specification.sourceAtomicSteps = [AtomicStep(model: .init(
            label: .init(name: "advance"), statements: statements))]
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let action = try #require(program.behavior.actions.first)
        let module = try program.renderModule().renderedModuleSource
        let header = "advance == "
        let declarations = module.split(separator: "\n").filter { $0.hasPrefix(header) }
        let declaration = try #require(declarations.count == 1 ? declarations[0].dropFirst(header.count) : nil)
        try StraightLineRenderedActionCheck.verify(action.body, rendered: String(declaration),
            layout: program.layout, binders: program.binderNames)
        #expect(try renderedResult(String(declaration), roots: roots)
            == sourceResult(statements, roots: roots))
        let wrong = String(declaration).replacingOccurrences(of: "== TRUE", with: "== FALSE")
        #expect(wrong != declaration)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: wrong,
                layout: program.layout, binders: program.binderNames)
        }
    }

    @Test("A stale pre-step read is rejected by the independent symbolic rule")
    func staleReadMutationChangesTheResult() throws {
        let roots = ["first", "second"]
        let specification = GeneratedAtomicCopyProofModel.spec
        let step = try #require(specification.sourceAtomicSteps.first)
        let source = step.model.statements
        let action = ActionNormalization.complete(
            try AlgorithmLowerer.lowerAtomicStep(step).action, variables: specification.variables)
        guard case .define(let first, let read, .define(let second, _, let writes)) = action else {
            throw InvalidShape.lowered
        }
        let stale = ActionExpr.define(first, read, .define(second, .variable("first"), writes))
        let expected = try sourceResult(source, roots: roots)
        try StraightLineAssignmentCheck.verify(step, lowered: action, stateRoots: Set(roots))
        try StraightLineAssignmentCheck.verify(step,
            lowered: .and(action, .unchanged(.named("untouched"))),
            stateRoots: Set(roots + ["untouched"]))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verify(step, lowered: stale, stateRoots: Set(roots))
        }
        #expect(try loweredResult(action, roots: roots) == expected)
        #expect(try loweredResult(stale, roots: roots) != expected)

        let inputs = try SourceTypeResolver().resolve(in: specification.compile())
        let compiled = try CompiledProgram(inputs: inputs)
        let compiledAction = try #require(compiled.behavior.actions.first)
        let untypedAction = try #require(inputs.semantics.behavior.actions.first)
        let loweredAction = try #require(specification.loweredSourceModel().actions.first)
        #expect(try compiledResult(compiledAction.body, program: compiled) == expected)
        try StraightLineAssignmentCheck.verifyCompiled(loweredAction, bindings: compiledAction.bindings,
            body: compiledAction.body, layout: compiled.layout)
        try StraightLineAssignmentCheck.verifyResolved(untypedAction,
            resolved: compiledAction, variableTypes: inputs.variableTypes,
            resolvedVariableTypes: compiled.variableTypes, resolvedBindingTypes: compiled.bindingTypes)
        guard case .define(let firstID, let firstRead, .define(let secondID, let secondRead, let compiledWrites))
                = compiledAction.body,
              let firstVariable = compiled.layout.variables.first(where: { $0.declaration.name == "first" })
        else { throw InvalidShape.lowered }
        let oldStateRead = CompiledExpression(operation: .stateVariable(firstVariable.id),
            resultType: secondRead.resultType, children: [])
        let staleCompiled = CompiledActionExpr.define(firstID, firstRead,
            .define(secondID, oldStateRead, compiledWrites))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyCompiled(loweredAction, bindings: compiledAction.bindings,
                body: staleCompiled, layout: compiled.layout)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolved(untypedAction,
                resolved: CompiledAction(id: compiledAction.id, bindings: compiledAction.bindings,
                    body: staleCompiled), variableTypes: inputs.variableTypes,
                resolvedVariableTypes: compiled.variableTypes, resolvedBindingTypes: compiled.bindingTypes)
        }
        #expect(try compiledResult(staleCompiled, program: compiled) != expected)
    }

    @Test("Bound action values retain ordered reads through source lowering")
    func boundValueFeedsLaterAssignment() throws {
        let variables = [NamedVar(name: "value", initial: .int(0)),
                         NamedVar(name: "copied", initial: .int(0))]
        let step = AtomicStep(model: .init(label: .init(name: "select"), statements: [
            .set(target: .root("value"), value: .variable("member")),
            .set(target: .root("copied"), value: .variable("value")),
        ]), bindings: [ActionBinding(name: "member", values: [.int(1), .int(2)])])
        let lowered = ActionNormalization.complete(
            try AlgorithmLowerer.lowerAtomicStep(step).action, variables: variables)
        try StraightLineAssignmentCheck.verify(step, lowered: lowered,
            stateRoots: ["value", "copied"])
        let stale = ActionExpr.and(
            .assign(.named("value"), .variable("member")),
            .assign(.named("copied"), .variable("copied")))
        do {
            try StraightLineAssignmentCheck.verify(step, lowered: stale,
                stateRoots: ["value", "copied"])
            Issue.record("A bound value was replaced by a stale pre-step read")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.select.orderedAssignments")
        }
        var specification = TLASpec(name: "BoundOrderedAssignments", variables: variables,
            actions: [], invariants: [])
        specification.sourceAtomicSteps = [step]
        let inputs = try SourceTypeResolver().resolve(in: specification.compile())
        let program = try CompiledProgram(inputs: inputs)
        let sourceAction = try #require(specification.loweredSourceModel().actions.first)
        let untypedAction = try #require(inputs.semantics.behavior.actions.first)
        let compiledAction = try #require(program.behavior.actions.first)
        #expect(untypedAction.id == compiledAction.id)
        let untypedBinding = try #require(untypedAction.bindings.first)
        #expect(untypedBinding.literalMembers?.count == 2,
            "Original binding domain: \(untypedBinding.domain.diagnosticName)")
        try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
            bindings: compiledAction.bindings, body: compiledAction.body, layout: program.layout)
        try StraightLineAssignmentCheck.verifyResolved(untypedAction,
            resolved: compiledAction, variableTypes: inputs.variableTypes,
            resolvedVariableTypes: program.variableTypes, resolvedBindingTypes: program.bindingTypes)
        let memberID = try #require(compiledAction.bindings.first?.binder)
        let valueID = try #require(program.layout.variables.first {
            $0.declaration.name == "value"
        }?.id)
        var replaced = 0
        let staleCompiled = compiledAction.body.map { expression in
            guard expression.operation == .boundValue(memberID) else { return expression }
            replaced += 1
            return CompiledExpression(operation: .stateVariable(valueID),
                resultType: expression.resultType, children: [])
        }
        #expect(replaced > 0)
        do {
            try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
                bindings: compiledAction.bindings, body: staleCompiled, layout: program.layout)
            Issue.record("The compiled action read the old state instead of its bound argument")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.select.compiledAssignments")
        }
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolved(untypedAction,
                resolved: .init(id: compiledAction.id, bindings: compiledAction.bindings,
                    body: staleCompiled), variableTypes: inputs.variableTypes,
                resolvedVariableTypes: program.variableTypes, resolvedBindingTypes: program.bindingTypes)
        }
        let binding = try #require(compiledAction.bindings.first)
        #expect(binding.domain.children.count == 2)
        let wrongMembers = binding.domain.children.enumerated().map { index, child in
            index == 1 ? CompiledExpression(operation: .value(.integer(3)),
                resultType: child.resultType, children: []) : child
        }
        let wrongBinding = CompiledActionBinding(binder: binding.binder,
            sourceName: binding.sourceName,
            domain: .init(operation: binding.domain.operation,
                resultType: binding.domain.resultType, children: wrongMembers),
            generatedSwiftType: binding.generatedSwiftType)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyCompiled(sourceAction,
                bindings: [wrongBinding], body: compiledAction.body, layout: program.layout)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolved(untypedAction,
                resolved: .init(id: compiledAction.id, bindings: [wrongBinding],
                    body: compiledAction.body), variableTypes: inputs.variableTypes,
                resolvedVariableTypes: program.variableTypes, resolvedBindingTypes: program.bindingTypes)
        }
    }

    @Test("The emitted TLA assignment action has the source's complete symbolic result")
    func renderedCopyKeepsOrderedReadsAndTargets() throws {
        let roots = ["first", "second"]
        let step = try #require(GeneratedAtomicCopyProofModel.spec.sourceAtomicSteps.first)
        let expected = try sourceResult(step.model.statements, roots: roots)
        let module = try GeneratedAtomicCopyProofModel.render().tlaBundle.root.tla
        let name = step.model.label.name
        let header = "\(name) == "
        let declarations = module.split(separator: "\n").filter { $0.hasPrefix(header) }
        let declaration = try #require(declarations.count == 1 ? declarations[0].dropFirst(header.count) : nil)
        #expect(module.contains("\nNext == \(name)\n"))
        #expect(try renderedResult(String(declaration), roots: roots) == expected)
        #expect(throws: InvalidShape.self) { try renderedResult("TRUE", roots: roots) }

        let stale = String(declaration).replacingOccurrences(
            of: "__atomic_1 == __atomic_0", with: "__atomic_1 == first")
        #expect(stale != declaration)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: GeneratedAtomicCopyProofModel.spec.compile()))
        let action = try #require(program.behavior.actions.first)
        try StraightLineRenderedActionCheck.verify(action.body, rendered: String(declaration),
            layout: program.layout, binders: program.binderNames)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: stale,
                layout: program.layout, binders: program.binderNames)
        }
        #expect(try renderedResult(stale, roots: roots) != expected)
    }
}
