import Foundation
import Testing
import SwiftParser
import SwiftSyntax
import SwiftTLAMacros
@testable import SwiftTLA
@testable import SwiftTLAPlugin

private enum OrderedAssignmentStep: String, CaseIterable, Sendable {
    case `switch`
}

@Suite("Ordered assignment lowering")
struct OrderedAssignmentLoweringTests {
    @Test("A standalone #spec checks its actual ordered Int builder output")
    func orderedIntSpecChecksRuntimeModel() throws {
        let spec = #spec("OrderedAssignment") {
            let algorithm = Algorithm(scoped: { scope in
                let first = scope.sharedVar(initial: 1)
                let second: SharedVariable<Int> = scope.sharedVar(initial: first + 2)
                Do(OrderedAssignmentStep.`switch`) {
                    Assign(first, to: second + 1)
                    Assign(second, to: first)
                }
            })
            algorithm
        }
        let compiled = try spec.compile()
        let secondID = try #require(compiled.layout.variables.first { $0.declaration.name == "second" }).id
        let secondInitial = try #require(compiled.semantics.behavior.initializations.first {
            $0.variable == secondID
        })
        guard case .value(let secondExpression) = secondInitial.initialization else {
            Issue.record("Expected the dependent Int initializer")
            return
        }
        #expect(StraightLineRenderedActionCheck.initialIntPredicate(
            secondExpression, named: "second", layout: compiled.layout) != nil)
        _ = try compiled.render()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let action = try #require(program.behavior.actions.first)
        var changedCapture = false
        let uncheckable = action.map { expression in
            guard !changedCapture, expression.resultType == .int else { return expression }
            changedCapture = true
            return CompiledExpression(operation: .value(.string("wrong")),
                resultType: .string, children: [])
        }
        #expect(changedCapture)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "OrderedAssignment", program: program))
        do {
            _ = try emitter.updateFunction(uncheckable, configurationParameters: "")
            Issue.record("A standalone #spec action bypassed its strict Swift output check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }

        let expected: [_OrderedIntSourceComponent] = [
            .variable(root: "first", initialization: .value(.int(1))),
            .variable(root: "second", initialization: .expression(.add(.variable("first"), .value(.int(2))))),
            .step(label: "switch", assignments: [
                (root: "first", value: .add(.variable("second"), .value(.int(1)))),
                (root: "second", value: .variable("first")),
            ]),
        ]
        for changed in [
            [expected[0], .variable(root: "second", initialization: .value(.int(3))), expected[2]],
            [expected[0], expected[1], .step(label: "other", assignments: [
                (root: "first", value: .add(.variable("second"), .value(.int(1)))),
                (root: "second", value: .variable("first")),
            ])],
            [expected[0], expected[1], .step(label: "switch", assignments: [
                (root: "second", value: .add(.variable("second"), .value(.int(1)))),
                (root: "second", value: .variable("first")),
            ])],
            [expected[0], expected[1], .step(label: "switch", assignments: [
                (root: "first", value: .add(.variable("first"), .value(.int(1)))),
                (root: "second", value: .variable("first")),
            ])],
            [expected[0], expected[1], .step(label: "switch", assignments: [
                (root: "second", value: .variable("first")),
                (root: "first", value: .add(.variable("second"), .value(.int(1)))),
            ])],
        ] {
            #expect(throws: SourceParseDiagnostic.self) {
                _ = try spec._checkingOrderedIntSource(algorithm: "algorithm", components: changed).compile()
            }
        }
    }

    @Test("The actual #spec witness rejects a builder that changes an initial value")
    func orderedIntSpecRejectsChangedBuilderOutput() {
        func Algorithm(
            _name name: String = "algorithm",
            @AlgorithmBuilder scoped body: (AlgorithmScope) -> [AlgorithmElement]
        ) -> SwiftTLA.Algorithm {
            SwiftTLA.Algorithm(_name: name, scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 2)
                Do(OrderedAssignmentStep.`switch`) {
                    Assign(value, to: value + 1)
                }
            })
        }

        let spec = #spec("ChangedBuilder") {
            let algorithm = Algorithm(scoped: { scope in
                let value = scope.sharedVar(initial: 1)
                Do(OrderedAssignmentStep.`switch`) {
                    Assign(value, to: value + 1)
                }
            })
            algorithm
        }
        #expect(throws: SourceParseDiagnostic.self) { _ = try spec.compile() }
    }

    @Test("The #spec rewrite preserves every ordered Int initializer and step")
    func orderedIntSpecRewriteRejectsDrift() throws {
        let source = """
        {
            let algorithm = Algorithm(scoped: { scope in
                let first = scope.sharedVar(initial: 1)
                let second = scope.sharedVar(_name: "second", initial: first + 2)
                Do(Step.copy) {
                    Assign(first, to: second + 1)
                    Assign(second, to: first)
                }
            })
            algorithm
        }
        """
        let expanded = source
            .replacingOccurrences(of: "Algorithm(scoped:",
                with: "Algorithm(_name: \"algorithm\", scoped:")
            .replacingOccurrences(of: "scope.sharedVar(initial: 1)",
                with: "scope.sharedVar(_name: \"first\", initial: 1)")
        let original = try parseSpecTestClosure(source)
        try OrderedIntSourceSyntaxCheck.verifyRewrite(original,
            rewritten: try parseSpecTestClosure(expanded))
        for changed in [
            expanded.replacingOccurrences(of: "_name: \"algorithm\"", with: "_name: \"other\""),
            expanded.replacingOccurrences(of: "_name: \"first\"", with: "_name: \"other\""),
            expanded.replacingOccurrences(of: "second + 1", with: "first + 1"),
            expanded.replacingOccurrences(of: "Assign(second, to: first)",
                with: "Assign(first, to: second)"),
            expanded.replacingOccurrences(of: "\n    algorithm\n", with: "\n    other\n"),
        ] {
            #expect(changed != expanded)
            #expect(throws: CompilationDiagnostic.self) {
                try OrderedIntSourceSyntaxCheck.verifyRewrite(original,
                    rewritten: try parseSpecTestClosure(changed))
            }
        }
    }

    @Test("Authored sequential Int syntax agrees with its parsed initial values and ordered steps")
    func authoredSequentialIntSyntaxRejectsDrift() throws {
        let source = """
        {
            let algorithm = Algorithm(scoped: { scope in
                let first = scope.sharedVar(initial: 1)
                let second = scope.sharedVar(initial: first + 2)
                Do(Step.copy) {
                    Assign(first, to: second + 1)
                    Assign(second, to: first)
                }
                Do(Step.finish) {
                    Assign(first, to: 0)
                }
            })
            algorithm
        }
        """
        let enums = [parserTestEnum("Step", cases: ["copy": .string("copy"),
            "finish": .string("finish")])]
        let original = try parseSpecTestClosure(source)
        let parsed = SpecParser.parseSpecClosure(named: "OrderedInt", original,
            sourceTypes: .init(enums: enums))
        #expect(parsed.diagnostics.isEmpty)
        try OrderedIntSourceSyntaxCheck.verify(original, parsed: parsed, enums: enums)
        let unused = source.replacingOccurrences(of: "algorithm\n",
            with: "let ignored = Algorithm(scoped: { scope in\n"
                + "    let value = scope.sharedVar(initial: 4)\n"
                + "    Do(Step.copy) { Assign(value, to: 5) }\n"
                + "})\nalgorithm\n")
        #expect(unused != source)
        try OrderedIntSourceSyntaxCheck.verify(try parseSpecTestClosure(unused),
            parsed: parsed, enums: enums)
        let reversed = source
            .replacingOccurrences(of: "Assign(first, to: second + 1)", with: "__FIRST__")
            .replacingOccurrences(of: "Assign(second, to: first)",
                with: "Assign(first, to: second + 1)")
            .replacingOccurrences(of: "__FIRST__", with: "Assign(second, to: first)")

        for changed in [
            source.replacingOccurrences(of: "initial: 1", with: "initial: 3"),
            source.replacingOccurrences(of: "initial: first + 2", with: "initial: first + 3"),
            source.replacingOccurrences(of: "Do(Step.copy)", with: "Do(Step.finish)"),
            source.replacingOccurrences(of: "Assign(first, to: second + 1)",
                with: "Assign(first, to: first + 1)"),
            source.replacingOccurrences(of: "Assign(second, to: first)",
                with: "Assign(first, to: second)"),
            reversed,
        ] {
            #expect(changed != source)
            #expect(throws: CompilationDiagnostic.self) {
                try OrderedIntSourceSyntaxCheck.verify(
                    try parseSpecTestClosure(changed), parsed: parsed, enums: enums)
            }
        }

        let labeled = source.replacingOccurrences(of: "scope.sharedVar(initial: 1)",
            with: "scope.sharedVar(label: \"First\", initial: 1)")
        let labeledSyntax = try parseSpecTestClosure(labeled)
        let labeledModel = SpecParser.parseSpecClosure(named: "OrderedInt", labeledSyntax,
            sourceTypes: .init(enums: enums))
        #expect(labeledModel.diagnostics.isEmpty)
        try OrderedIntSourceSyntaxCheck.verify(labeledSyntax, parsed: labeledModel, enums: enums)
        let wrongLabeledInitial = labeled.replacingOccurrences(of: "initial: 1", with: "initial: 3")
        #expect(throws: CompilationDiagnostic.self) {
            try OrderedIntSourceSyntaxCheck.verify(try parseSpecTestClosure(wrongLabeledInitial),
                parsed: labeledModel, enums: enums)
        }
    }

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

    @Test("Each source assignment target has one final lowered write")
    func duplicateFinalWriteIsRejected() throws {
        let step = AtomicStep(model: .init(label: .init(name: "advance"), statements: [
            .set(target: .root("value"), value: .value(.int(1))),
        ]))
        let lowered = try AlgorithmLowerer.lowerAtomicStep(step).action
        try StraightLineAssignmentCheck.verify(step, lowered: lowered, stateRoots: ["value"])
        let duplicate = ActionExpr.and(lowered, .assign(.named("value"), .value(.int(1))))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verify(step, lowered: duplicate, stateRoots: ["value"])
        }
    }

    @Test("Nested addition retains its compiled operands and guarded TLA+ action")
    func nestedAdditionPreservesCompiledExpression() throws {
        let expression = StateExpr.add(.variable("value"),
            .add(.variable("offset"), .value(.int(1))))
        let step = AtomicStep(model: .init(label: .init(name: "advance"), statements: [
            .set(target: .root("value"), value: expression),
        ]))
        var specification = TLASpec(name: "OrderedAddition", variables: [
            NamedVar(name: "value", initial: .int(0)),
            NamedVar(name: "offset", initial: .int(2)),
        ], actions: [], invariants: [])
        specification.sourceAtomicSteps = [step]
        let inputs = try SourceTypeResolver().resolve(in: specification.compile())
        let program = try CompiledProgram(inputs: inputs)
        let source = try #require(specification.loweredSourceModel().actions.first)
        let untyped = try #require(inputs.semantics.behavior.actions.first)
        let action = try #require(program.behavior.actions.first)
        try StraightLineAssignmentCheck.verifyCompiled(source, bindings: action.bindings,
            body: action.body, layout: program.layout)
        try StraightLineAssignmentCheck.verifyResolved(untyped, resolved: action,
            variableTypes: inputs.variableTypes, resolvedVariableTypes: program.variableTypes,
            resolvedBindingTypes: program.bindingTypes)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "OrderedAddition", program: program))
        _ = try emitter.machineMembers()

        guard case .define(let binder, let sum, let body) = action.body,
              sum.operation == .add, sum.children.count == 2 else { throw InvalidShape.lowered }
        let wrongOperation = CompiledExpression(operation: .subtract,
            resultType: sum.resultType, children: sum.children)
        let changed = CompiledActionExpr.define(binder, wrongOperation, body)
        do {
            try StraightLineAssignmentCheck.verifyCompiled(source, bindings: action.bindings,
                body: changed, layout: program.layout)
            Issue.record("A changed addition operation passed source-to-compiled verification")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.advance.compiledAssignments")
        }
        let reversed = CompiledActionExpr.define(binder,
            .init(operation: .add, resultType: sum.resultType,
                children: Array(sum.children.reversed())), body)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyCompiled(source, bindings: action.bindings,
                body: reversed, layout: program.layout)
        }

        let wrongType = CompiledExpression(operation: sum.operation,
            resultType: .bool, children: sum.children)
        do {
            try StraightLineAssignmentCheck.verifyResolved(untyped,
                resolved: .init(id: action.id, bindings: action.bindings,
                    body: .define(binder, wrongType, body)), variableTypes: inputs.variableTypes,
                resolvedVariableTypes: program.variableTypes,
                resolvedBindingTypes: program.bindingTypes)
            Issue.record("A changed addition result type passed typed-resolution verification")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions[\(action.id.ordinal)].resolvedAssignments")
        }

        let output = try program.renderModule()
        let module = output.renderedModuleSource
        let header = "advance == "
        let declarations = module.split(separator: "\n").filter { $0.hasPrefix(header) }
        let rendered = String(try #require(declarations.count == 1
            ? declarations[0].dropFirst(header.count) : nil))
        try StraightLineRenderedActionCheck.verify(action.body, rendered: rendered,
            layout: program.layout, binders: program.binderNames)
        try StraightLineRenderedActionCheck.verifyDeclaration(action, named: "advance",
            body: rendered, module: module, layout: program.layout, binders: program.binderNames,
            failureDeclarations: output.evaluationFailureDeclarations)
        for prefix in ["__SwiftTLAOverflowFailure0_1 == ",
                       "__SwiftTLAOverflowOperands0_1 == ",
                       "__SwiftTLAOverflowOperation0_1 == ",
                       "__SwiftTLAAnyEvaluationFailure0 == "] {
            let line = try #require(module.split(separator: "\n").first { $0.hasPrefix(prefix) })
            let replacement = "\(prefix)FALSE"
            let corrupted = module.replacingOccurrences(of: String(line), with: replacement)
            let wrongDeclarations = output.evaluationFailureDeclarations.map {
                $0 == String(line) ? replacement : $0
            }
            #expect(corrupted != module)
            #expect(wrongDeclarations != output.evaluationFailureDeclarations)
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineRenderedActionCheck.verifyDeclaration(action, named: "advance",
                    body: rendered, module: corrupted, layout: program.layout,
                    binders: program.binderNames,
                    failureDeclarations: wrongDeclarations)
            }
        }
        let wrongValue = rendered.replacingOccurrences(of: "(offset + 1)", with: "(offset - 1)")
        #expect(wrongValue != rendered)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: wrongValue,
                layout: program.layout, binders: program.binderNames)
        }
        let wrongGuard = rendered.replacingOccurrences(
            of: "offset <= 1000000000", with: "offset <= 999999999")
        #expect(wrongGuard != rendered)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: wrongGuard,
                layout: program.layout, binders: program.binderNames)
        }
    }

    @Test("One fallible assignment retains its complete expression and captured write")
    func fallibleSingleAssignmentRetainsOneCapture() throws {
        let expression = StateExpr.divide(
            .add(.variable("value"), .value(.int(1))), .variable("divisor"))
        let step = AtomicStep(model: .init(label: .init(name: "advance"), statements: [
            .set(target: .root("value"), value: expression),
        ]))
        let action = try AlgorithmLowerer.lowerAtomicStep(step).action
        try StraightLineAssignmentCheck.verify(step, lowered: action,
            stateRoots: ["value", "divisor"])
        guard case .define(let binder, _, let body) = action else {
            throw InvalidShape.lowered
        }
        let changedExpression = StateExpr.divide(
            .add(.variable("divisor"), .value(.int(1))), .variable("divisor"))
        do {
            try StraightLineAssignmentCheck.verify(step,
                lowered: .define(binder, changedExpression, body),
                stateRoots: ["value", "divisor"])
            Issue.record("A changed source expression passed the assignment capture check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.advance.singleAssignmentCapture")
        }
        let owner = ControlOwner.sequential(algorithm: "OrderedAssignment")
        let entry = ControlLocationReference(owner: owner, sourceName: "advance")
        let next = ControlLocationReference(owner: owner, sourceName: "done")
        let guardControl = ActionExpr.guard_(.equal(.programCounter, .controlLocation(entry)))
        let writeControl = ActionExpr.assign(.programCounter, .controlLocation(next))
        try StraightLineAssignmentCheck.verify(step,
            lowered: .and(guardControl, .and(action, writeControl)),
            stateRoots: ["value", "divisor"], control: (entry, next))
        do {
            try StraightLineAssignmentCheck.verify(step,
                lowered: .and(action, .and(guardControl, writeControl)),
                stateRoots: ["value", "divisor"], control: (entry, next))
            Issue.record("A disabled action could evaluate a fallible capture before its control guard")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.advance.singleAssignmentCapture")
        }
        let outOfScope = ActionExpr.and(
            .assign(.named("value"), .variable(binder)),
            .define(binder, expression, .guard_(.bool(true))))
        do {
            try StraightLineAssignmentCheck.verify(step, lowered: outOfScope,
                stateRoots: ["value", "divisor"])
            Issue.record("A captured value used outside its binding passed the assignment check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.advance.singleAssignmentCapture")
        }
        do {
            try StraightLineAssignmentCheck.verify(step,
                lowered: .define(binder, expression, .define("extra", expression, body)),
                stateRoots: ["value", "divisor"])
            Issue.record("A duplicated fallible evaluation passed the assignment capture check")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "actions.advance.singleAssignmentCapture")
        }
    }

    @Test("A control-free #spec loop preserves ordered source writes through both emitters")
    func authoredLoopPreservesOrderedWrites() throws {
        let specification = OrderedAlgorithmCopyProofModel.spec
        let sourceStep = try #require(specification.sourceAlgorithms.first?.model.sequentialSteps.first)
        let roots = ["first", "second"]
        let expected = try sourceResult(sourceStep.statements, roots: roots)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let action = try #require(program.behavior.actions.first)
        #expect(try compiledResult(action.body, program: program) == expected)

        let module = try program.renderModule().renderedModuleSource
        let header = "copy == "
        let declarations = module.split(separator: "\n").filter { $0.hasPrefix(header) }
        let declaration = try #require(declarations.count == 1 ? declarations[0].dropFirst(header.count) : nil)
        try StraightLineRenderedActionCheck.verify(action.body, rendered: String(declaration),
            layout: program.layout, binders: program.binderNames)
        #expect(try renderedResult(String(declaration), roots: roots) == expected)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "OrderedAlgorithmCopyProofModel", program: program))
        _ = try emitter.machineMembers()

        let machine = try OrderedAlgorithmCopyProofModel.makeMachine()
        #expect(machine.state.first == 1 && machine.state.second == 2)
        let successors = try machine.successors(for: .copy)
        #expect(successors.count == 1)
        #expect(successors.first?.state.first == 2)
        #expect(successors.first?.state.second == 2)

        let lowered = try #require(specification.loweredSourceModel().actions.first)
        let duplicate = ActionExpr.and(lowered.body, .assign(.named("first"), .variable("second")))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verify(AtomicStep(model: sourceStep),
                lowered: duplicate, stateRoots: Set(roots))
        }
    }

    @Test("A sequential Do step preserves its complete control location in both outputs")
    func sequentialStepPreservesControlLocation() throws {
        let specification = SequentialCopyProofModel.spec
        let source = try #require(specification.sourceAlgorithms.first?.model)
        let lowered = try specification.loweredSourceModel()
        let provedActions = try StraightLineAssignmentCheck.verifySequential(source, lowered: lowered,
            enumerateInitialControl: false)
        #expect(provedActions == Set(["copy", "finish",
            CompilerControlSymbol.terminatingAction.rawValue]))
        #expect(lowered.orderedIntProofActionNames == provedActions)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let action = try #require(program.behavior.actions.first)
        let module = try program.renderModule().renderedModuleSource
        let header = "copy == "
        let declarations = module.split(separator: "\n").filter { $0.hasPrefix(header) }
        let body = try #require(declarations.count == 1 ? String(declarations[0].dropFirst(header.count)) : nil)
        try StraightLineRenderedActionCheck.verify(action.body, rendered: body,
            layout: program.layout, binders: program.binderNames, required: true)
        let wrongGuard = body.replacingOccurrences(of: "pc = \"copy\"", with: "pc = \"finish\"")
        #expect(wrongGuard != body)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: wrongGuard,
                layout: program.layout, binders: program.binderNames)
        }
        let wrongTarget = body.replacingOccurrences(of: "pc' = \"finish\"", with: "pc' = \"copy\"")
        #expect(wrongTarget != body)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: wrongTarget,
                layout: program.layout, binders: program.binderNames)
        }

        let terminalAction = try #require(program.behavior.actions.last)
        let terminalName = try #require(program.layout.actions.first {
            $0.id == terminalAction.id
        }?.renderedName)
        let terminalHeader = "\(terminalName) == "
        let terminalDeclarations = module.split(separator: "\n").filter {
            $0.hasPrefix(terminalHeader)
        }
        let terminalBody = try #require(terminalDeclarations.count == 1
            ? String(terminalDeclarations[0].dropFirst(terminalHeader.count)) : nil)
        try StraightLineRenderedActionCheck.verify(terminalAction.body, rendered: terminalBody,
            layout: program.layout, binders: program.binderNames, required: true)
        let wrongTerminalBody = terminalBody.replacingOccurrences(of: "pc = \"Done\"",
            with: "pc = \"copy\"")
        #expect(wrongTerminalBody != terminalBody)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(terminalAction.body, rendered: wrongTerminalBody,
                layout: program.layout, binders: program.binderNames)
        }

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SequentialCopyProofModel", program: program))
        let visitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let parts = try emitter.actionFunctions(action.body)
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: parts.writes)
        #expect(program.requiresOrderedIntOutput(action.id))
        var changedCapture = false
        let uncheckable = action.map { expression in
            guard !changedCapture, expression.resultType == .int else { return expression }
            changedCapture = true
            return CompiledExpression(operation: .value(.string("wrong")),
                resultType: .string, children: [])
        }
        #expect(changedCapture)
        do {
            _ = try emitter.updateFunction(uncheckable, configurationParameters: "")
            Issue.record("An uncheckable ordered Int capture passed native output verification")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.hasPrefix("native.action.binding."))
        }
        let wrongSwiftGuard = visitor.description.replacingOccurrences(
            of: " == _ControlLocation.", with: " != _ControlLocation.")
        #expect(wrongSwiftGuard != visitor.description)
        let wrongGuardVisitor = try #require(Parser.parse(source: wrongSwiftGuard)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(wrongGuardVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: parts.writes)
        }
        let controlWrite = try #require(parts.writes.first {
            $0.value.hasPrefix("_ControlLocation.location")
        })
        let wrongLocation = "_ControlLocation.location999"
        let wrongSwiftWrite = visitor.description.replacingOccurrences(
            of: "\(controlWrite.slot): \(controlWrite.value)",
            with: "\(controlWrite.slot): \(wrongLocation)")
        #expect(wrongSwiftWrite != visitor.description)
        let wrongWriteVisitor = try #require(Parser.parse(source: wrongSwiftWrite)
            .statements.first?.item.as(DeclSyntax.self))
        let wrongParts = parts.writes.map { part in
            (id: part.id, slot: part.slot,
             value: part.id == controlWrite.id ? wrongLocation : part.value)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(wrongWriteVisitor, action: action.body,
                program: program, stateFields: emitter.stateMemberNames, parts: wrongParts)
        }

        let terminalVisitor = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text
                == "_visitUpdates\(terminalAction.id.ordinal)"
        })
        let terminalParts = try emitter.actionFunctions(terminalAction.body)
        try verifyGeneratedActionWriteOutput(terminalVisitor, action: terminalAction.body,
            program: program, stateFields: emitter.stateMemberNames, parts: terminalParts.writes)
        let wrongTerminalVisitor = terminalVisitor.description.replacingOccurrences(
            of: " == _ControlLocation.", with: " != _ControlLocation.")
        #expect(wrongTerminalVisitor != terminalVisitor.description)
        let wrongTerminalDeclaration = try #require(Parser.parse(source: wrongTerminalVisitor)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(wrongTerminalDeclaration,
                action: terminalAction.body, program: program,
                stateFields: emitter.stateMemberNames, parts: terminalParts.writes)
        }

        let machine = try SequentialCopyProofModel.makeMachine()
        let pc = try #require(TLAStateProjection.Token(validating: "pc"))
        #expect(try machine.formalProjection(of: machine.snapshot).value(for: pc) == .string("copy"))
        let successors = try machine.successors(for: .copy)
        let successor = try #require(successors.count == 1 ? successors.first : nil)
        #expect(successor.state.first == 2 && successor.state.second == 2)
        #expect(try successor.formalProjection(of: successor.snapshot).value(for: pc)
            == .string("finish"))

        var changed = 0
        func wrongNext(_ action: ActionExpr) -> ActionExpr {
            switch action {
            case .assign(.programCounter, .controlLocation):
                changed += 1
                return .assign(.programCounter, .controlLocation(.init(
                    owner: .sequential(algorithm: source.name), sourceName: "copy")))
            case .and(let left, let right): return .and(wrongNext(left), wrongNext(right))
            case .define(let name, let value, let body): return .define(name, value, wrongNext(body))
            default: return action
            }
        }
        var mutated = lowered
        mutated.actions[0] = NamedAction(name: "copy", body: wrongNext(lowered.actions[0].body))
        #expect(changed == 1)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifySequential(source, lowered: mutated,
                enumerateInitialControl: false)
        }

        var wrongInitial = lowered
        wrongInitial.variables[0] = NamedVar(name: "pc", initialization: .expression(
            .controlLocation(.init(owner: .sequential(algorithm: source.name), sourceName: "finish"))),
            origin: .programCounter)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifySequential(source, lowered: wrongInitial,
                enumerateInitialControl: false)
        }
        var wrongSharedInitial = lowered
        let first = try #require(wrongSharedInitial.variables.firstIndex { $0.name == "first" })
        wrongSharedInitial.variables[first] = NamedVar(name: "first", initial: .int(9))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifySequential(source, lowered: wrongSharedInitial,
                enumerateInitialControl: false)
        }
        var wrongLabel = lowered
        wrongLabel.actions[0] = NamedAction(name: "other", body: lowered.actions[0].body)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifySequential(source, lowered: wrongLabel,
                enumerateInitialControl: false)
        }

        let terminalIndex = lowered.actions.count - 1
        let terminal = lowered.actions[terminalIndex]
        func replacingTerminal(_ action: ActionExpr, guardLocation: Bool) -> ActionExpr {
            switch action {
            case .guard_(.equal(.programCounter, .controlLocation)) where guardLocation:
                return .guard_(.equal(.programCounter, .controlLocation(.init(
                    owner: .sequential(algorithm: source.name), sourceName: "copy"))))
            case .unchanged(.named("first")) where !guardLocation:
                return .assign(.named("first"), .value(.int(9)))
            case .and(let left, let right):
                return .and(replacingTerminal(left, guardLocation: guardLocation),
                    replacingTerminal(right, guardLocation: guardLocation))
            default: return action
            }
        }
        for guardLocation in [true, false] {
            let wrongBody = replacingTerminal(terminal.body, guardLocation: guardLocation)
            #expect(wrongBody != terminal.body)
            var wrongTerminal = lowered
            wrongTerminal.actions[terminalIndex] = NamedAction(name: terminal.name,
                body: wrongBody, isTermination: true)
            #expect(throws: CompilationDiagnostic.self) {
                try StraightLineAssignmentCheck.verifySequential(source, lowered: wrongTerminal,
                    enumerateInitialControl: false)
            }
        }
    }

    @Test("An ordered Int #spec retains default deadlock checking in both outputs")
    func orderedIntSourceRetainsDefaultDeadlockChecking() throws {
        let specification = SequentialCopyProofModel.spec
        let compiled = try specification.compile()
        let cfg = try compiled.render().tlaBundle.cfg
        #expect(cfg.contains("CHECK_DEADLOCK TRUE\n"))

        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SequentialCopyProofModel", program: program))
        let declarations = try emitter.propertyDeclarations(configurationParameters: "")
        let deadlock = try #require(declarations.first {
            $0.as(VariableDeclSyntax.self)?.bindings.first?.pattern
                .as(IdentifierPatternSyntax.self)?.identifier.text == "checksDeadlock"
        })
        try verifyGeneratedSourceDefaultDeadlock(deadlock, required: true)
        let flippedSwift = deadlock.description.replacingOccurrences(of: "true", with: "false")
        #expect(flippedSwift != deadlock.description)
        let flippedDeclaration = try #require(Parser.parse(source: flippedSwift)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedSourceDefaultDeadlock(flippedDeclaration, required: true)
        }
        let export = try #require(try emitter.exportDeclarations().first)
        try verifyGeneratedExportDefaultDeadlock(export, required: true)
        let flippedExport = export.description.replacingOccurrences(
            of: "checkDeadlock: true", with: "checkDeadlock: false")
        #expect(flippedExport != export.description)
        let flippedExportDeclaration = try #require(Parser.parse(source: flippedExport)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedExportDefaultDeadlock(flippedExportDeclaration, required: true)
        }
        let decoyExport = flippedExport.replacingOccurrences(of: "return _rendered",
            with: "_ = decoy(checkDeadlock: true)\nreturn _rendered")
        let decoyDeclaration = try #require(Parser.parse(source: decoyExport)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedExportDefaultDeadlock(decoyDeclaration, required: true)
        }
        let changedReturn = export.description.replacingOccurrences(of: "return _rendered",
            with: "return try _rendered.selectingChecks(ModelChecks<String>(properties: [], checkDeadlock: false), formalPropertyNames: [:])")
        #expect(changedReturn != export.description)
        let changedReturnDeclaration = try #require(Parser.parse(source: changedReturn)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedExportDefaultDeadlock(changedReturnDeclaration, required: true)
        }
        #expect(try SequentialCopyProofModel.render().tlaBundle.cfg.contains("CHECK_DEADLOCK TRUE\n"))

        var flippedSource = specification
        flippedSource.checkDeadlock = false
        #expect(throws: CompilationDiagnostic.self) {
            try flippedSource.compile().render()
        }
        let configuration = try program.renderModule().configuration
        let flippedCFG = cfg.replacingOccurrences(
            of: "CHECK_DEADLOCK TRUE", with: "CHECK_DEADLOCK FALSE")
        #expect(flippedCFG != cfg)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifySourceDefaultDeadlock(configuration,
                rendered: flippedCFG, required: true)
        }
    }

    @Test("Authored data and control initializers retain their identities through compilation")
    func authoredInitializersRetainCompiledValues() throws {
        let sourceModel = try SequentialCopyProofModel.spec.loweredSourceModel()
        let source = try #require(sourceModel.variables.first {
            $0.name == "first"
        })
        let inputs = try SourceTypeResolver().resolve(in: SequentialCopyProofModel.spec.compile())
        let variable = try #require(inputs.layout.variables.first { $0.declaration.name == "first" })
        let lowered = try #require(inputs.semantics.behavior.initializations.first {
            $0.variable == variable.id
        }?.initialization)
        let program = try CompiledProgram(inputs: inputs)
        let resolved = try #require(program.behavior.initializations.first {
            $0.variable == variable.id
        }?.initialization)
        let path = "variables.first.initialization"
        try StraightLineAssignmentCheck.verifyInitialIntExpression(source.initialization,
            lowered: lowered, layout: inputs.layout, at: path)
        try StraightLineAssignmentCheck.verifyResolvedInitialIntExpression(lowered,
            resolved: resolved, at: path)

        let wrongValue = CompiledVariableInitialization.value(.value(.integer(9)))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyInitialIntExpression(source.initialization,
                lowered: wrongValue, layout: inputs.layout, at: path)
        }
        let wrongResolvedValue = CompiledVariableInitialization.value(.init(
            operation: .value(.integer(9)), resultType: .int, children: []))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolvedInitialIntExpression(lowered,
                resolved: wrongResolvedValue, at: path)
        }
        let wrongType = CompiledVariableInitialization.value(.init(
            operation: .value(.integer(1)), resultType: .bool, children: []))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolvedInitialIntExpression(lowered,
                resolved: wrongType, at: path)
        }

        let control = try #require(sourceModel.variables.first { $0.origin == .programCounter })
        let controlVariable = try #require(inputs.layout.variables.first {
            $0.declaration.origin == .programCounter
        })
        let loweredControl = try #require(inputs.semantics.behavior.initializations.first {
            $0.variable == controlVariable.id
        }?.initialization)
        let resolvedControl = try #require(program.behavior.initializations.first {
            $0.variable == controlVariable.id
        }?.initialization)
        let controlPath = "variables.\(control.name).initialization"
        try StraightLineAssignmentCheck.verifyInitialControlLocation(control.initialization,
            lowered: loweredControl, layout: inputs.layout, at: controlPath)
        try StraightLineAssignmentCheck.verifyResolvedInitialControlLocation(loweredControl,
            resolved: resolvedControl, at: controlPath)
        let wrongLocation = try #require(inputs.layout.controlLocations.first {
            $0.sourceName == "finish"
        })
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyInitialControlLocation(control.initialization,
                lowered: .value(.controlLocation(wrongLocation.id)),
                layout: inputs.layout, at: controlPath)
        }
        let wrongResolvedControl = CompiledVariableInitialization.value(.init(
            operation: .controlLocation(wrongLocation.id), resultType: .controlLocation, children: []))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolvedInitialControlLocation(loweredControl,
                resolved: wrongResolvedControl, at: controlPath)
        }

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SequentialCopyProofModel", program: program))
        let nativeInitial = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let slot = emitter.variable(controlVariable.id)
        let bindings = program.behavior.initializations.map { "let \(emitter.variable($0.variable))" }
        guard case .value(let initialControlExpression) = resolvedControl,
              case .controlLocation(let initialControlID) = initialControlExpression.operation else {
            throw InvalidShape.lowered
        }
        let expectedControl = [slot: initialControlID.ordinal]
        try verifyGeneratedInitialBindings(nativeInitial, expected: bindings,
            expectedLoops: [:], expectedCandidateSources: [:],
            expectedControlLocations: expectedControl)
        let originalBinding = "let \(slot): _ControlLocation = _ControlLocation.location\(initialControlID.ordinal)"
        let wrongBinding = "let \(slot): _ControlLocation = _ControlLocation.location\(wrongLocation.id.ordinal)"
        let wrongNative = nativeInitial.description.replacingOccurrences(of: originalBinding,
            with: wrongBinding)
        #expect(wrongNative != nativeInitial.description)
        let wrongNativeDeclaration = try #require(Parser.parse(source: wrongNative)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedInitialBindings(wrongNativeDeclaration, expected: bindings,
                expectedLoops: [:], expectedCandidateSources: [:],
                expectedControlLocations: expectedControl)
        }

        let module = try program.renderModule().renderedModuleSource
        let initialLines = module.components(separatedBy: "\n")
        let start = try #require(initialLines.firstIndex(of: "Init =="))
        let end = initialLines[(start + 1)...].firstIndex(of: "") ?? initialLines.count
        let predicates = initialLines[(start + 1)..<end].map {
            String($0.dropFirst("  /\\ ".count))
        }
        let expectedFormalControl = try #require(inputs.layout.controlLocations.first {
            $0.id == initialControlID
        }?.formalName)
        try verifyRenderedInitialConjunction(module, predicates: predicates,
            expectedControlLocations: [control.name: expectedFormalControl])
        let initialClause = "\(control.name) = \(TLAValue.string(expectedFormalControl).description)"
        let wrongClause = "\(control.name) = \(TLAValue.string(wrongLocation.formalName).description)"
        let wrongModule = module.replacingOccurrences(of: initialClause, with: wrongClause)
        #expect(wrongModule != module)
        #expect(throws: CompilationDiagnostic.self) {
            try verifyRenderedInitialConjunction(wrongModule, predicates: predicates.map {
                $0.replacingOccurrences(of: initialClause, with: wrongClause)
            }, expectedControlLocations: [control.name: expectedFormalControl])
        }

        let literals = ["first": 1, "second": 2]
        try verifyRenderedInitialConjunction(module, predicates: predicates,
            expectedIntLiterals: literals,
            expectedControlLocations: [control.name: expectedFormalControl],
            requireCompleteSimpleInitials: true)
        let originalInit = (["Init =="] + predicates.map { "  /\\ \($0)" }).joined(separator: "\n")
        let extraInit = originalInit + "\n  /\\ FALSE"
        let extraModule = module.replacingOccurrences(of: originalInit, with: extraInit)
        #expect(extraModule != module)
        let extraPredicates = predicates + ["FALSE"]
        try verifyRenderedInitialConjunction(extraModule, predicates: extraPredicates,
            expectedIntLiterals: literals,
            expectedControlLocations: [control.name: expectedFormalControl])
        do {
            try verifyRenderedInitialConjunction(extraModule, predicates: extraPredicates,
                expectedIntLiterals: literals,
                expectedControlLocations: [control.name: expectedFormalControl],
                requireCompleteSimpleInitials: true)
            Issue.record("An extra Init conjunct discarded the compiled initial state")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Init")
        }
    }

    @Test("Dependent Int initialization retains complete sequential control checking")
    func dependentIntInitializerRetainsTerminalControl() throws {
        let specification = SequentialDependentIntInitialProofModel.spec
        let source = try #require(specification.sourceAlgorithms.first?.model)
        let lowered = try specification.loweredSourceModel()
        _ = try StraightLineAssignmentCheck.verifySequential(source, lowered: lowered,
            enumerateInitialControl: false)
        let terminal = try #require(lowered.actions.last)
        var changed = 0
        func wrongGuard(_ action: ActionExpr) -> ActionExpr {
            switch action {
            case .guard_(.equal(.programCounter, .controlLocation)):
                changed += 1
                return .guard_(.value(.bool(true)))
            case .and(let left, let right): return .and(wrongGuard(left), wrongGuard(right))
            default: return action
            }
        }
        var mutated = lowered
        mutated.actions[mutated.actions.count - 1] = NamedAction(
            name: terminal.name, body: wrongGuard(terminal.body),
            bindings: terminal.bindings, isTermination: true)
        #expect(changed == 1)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifySequential(source, lowered: mutated,
                enumerateInitialControl: false)
        }
    }

    @Test("Dependent Int initialization retains its ordered source expression through compilation")
    func dependentIntInitializerRetainsExpression() throws {
        let source = StateExpr.add(.add(.variable("first"), .value(.int(2))), .value(.int(1)))
        let specification = SequentialDependentIntInitialProofModel.spec
        let inputs = try SourceTypeResolver().resolve(in: specification.compile())
        let program = try CompiledProgram(inputs: inputs)
        let variable = try #require(inputs.layout.variables.first { $0.declaration.name == "second" })
        let lowered = try #require(inputs.semantics.behavior.initializations.first {
            $0.variable == variable.id
        }?.initialization)
        let resolved = try #require(program.behavior.initializations.first {
            $0.variable == variable.id
        }?.initialization)
        let path = "variables.second.initialization"
        try StraightLineAssignmentCheck.verifyInitialIntExpression(.expression(source),
            lowered: lowered, layout: inputs.layout, at: path)
        try StraightLineAssignmentCheck.verifyResolvedInitialIntExpression(lowered,
            resolved: resolved, at: path)

        guard case .value(let loweredExpression) = lowered,
              case .value(let resolvedExpression) = resolved else { throw InvalidShape.lowered }
        let reversed = CompiledVariableInitialization.value(.init(operation: .add,
            resultType: loweredExpression.resultType,
            children: Array(loweredExpression.children.reversed())))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyInitialIntExpression(.expression(source),
                lowered: reversed, layout: inputs.layout, at: path)
        }
        let wrongResolved = CompiledVariableInitialization.value(.init(operation: .add,
            resultType: resolvedExpression.resultType,
            children: [.init(operation: .value(.integer(3)), resultType: .int, children: []),
                resolvedExpression.children[1]]))
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyResolvedInitialIntExpression(lowered,
                resolved: wrongResolved, at: path)
        }

        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SequentialDependentIntInitialProofModel", program: program))
        let declaration = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        let slots = Dictionary(uniqueKeysWithValues: program.layout.variables.map {
            ($0.id, emitter.variable($0.id))
        })
        let name = emitter.variable(variable.id)
        let bindings = program.behavior.initializations.map { "let \(emitter.variable($0.variable))" }
        func verify(_ declaration: DeclSyntax) throws {
            try verifyGeneratedInitialBindings(declaration, expected: bindings,
                expectedLoops: [:], expectedCandidateSources: [:],
                expectedIntExpressions: [name: resolvedExpression], stateSlots: slots)
            try emitter.verifyDeterministicIntInitialOutput(declaration)
        }
        try verify(declaration)
        try verifyOrderedIntInitialExpression(declaration,
            named: name, expression: resolvedExpression, slots: slots)
        let missingFailure = declaration.description.replacingOccurrences(
            of: "if firstFailure == nil { firstFailure = failure }", with: "")
        #expect(missingFailure != declaration.description)
        let missingFailureDeclaration = try #require(Parser.parse(source: missingFailure)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verify(missingFailureDeclaration)
        }
        let wrongSwift = declaration.description.replacingOccurrences(
            of: "_NativeMachineOperations.add", with: "_NativeMachineOperations.subtract")
        #expect(wrongSwift != declaration.description)
        let wrongDeclaration = try #require(Parser.parse(source: wrongSwift)
            .statements.first?.item.as(DeclSyntax.self))
        do {
            try verify(wrongDeclaration)
            Issue.record("A changed generated initializer operation was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.value.\(name)")
        }
        let wrongOrder = declaration.description.replacingOccurrences(
            of: "_NativeMachineOperations.add(_arithmetic0, _arithmetic1)",
            with: "_NativeMachineOperations.add(_arithmetic1, _arithmetic0)")
        #expect(wrongOrder != declaration.description)
        let wrongOrderDeclaration = try #require(Parser.parse(source: wrongOrder)
            .statements.first?.item.as(DeclSyntax.self))
        #expect(throws: CompilationDiagnostic.self) {
            try verifyOrderedIntInitialExpression(wrongOrderDeclaration,
                named: name, expression: resolvedExpression, slots: slots)
        }

        let module = try program.renderModule().renderedModuleSource
        let lines = module.components(separatedBy: "\n")
        let start = try #require(lines.firstIndex(of: "Init =="))
        let end = lines[(start + 1)...].firstIndex(of: "") ?? lines.count
        let predicates = lines[(start + 1)..<end].map {
            String($0.dropFirst("  /\\ ".count))
        }
        let expectedPredicate = try #require(StraightLineRenderedActionCheck.initialIntPredicate(
            resolvedExpression, named: "second", layout: program.layout))
        let controls = program.behavior.initializations.compactMap {
            initialization -> (String, String)? in
            guard case .value(let expression) = initialization.initialization,
                  case .controlLocation(let location) = expression.operation,
                  let variable = program.layout.variables.first(where: { $0.id == initialization.variable }),
                  let formal = program.layout.controlLocation(location)?.formalName else { return nil }
            return (variable.declaration.name, formal)
        }
        let control = try #require(controls.first)
        try verifyRenderedInitialConjunction(module, predicates: predicates,
            expectedIntLiterals: ["first": 1],
            expectedControlLocations: [control.0: control.1],
            expectedIntPredicates: ["second": expectedPredicate],
            requireCompleteSimpleInitials: true)
        let completeInit = (["Init =="] + predicates.map { "  /\\ \($0)" }).joined(separator: "\n")
        let extraModule = module.replacingOccurrences(of: completeInit,
            with: completeInit + "\n  /\\ FALSE")
        #expect(extraModule != module)
        #expect(throws: CompilationDiagnostic.self) {
            try verifyRenderedInitialConjunction(extraModule, predicates: predicates + ["FALSE"],
                expectedIntLiterals: ["first": 1],
                expectedControlLocations: [control.0: control.1],
                expectedIntPredicates: ["second": expectedPredicate],
                requireCompleteSimpleInitials: true)
        }
        let wrongPredicate = expectedPredicate.replacingOccurrences(
            of: "second = ((first + 2) + 1)", with: "second = ((first + 3) + 1)")
        #expect(wrongPredicate != expectedPredicate)
        let wrongModule = module.replacingOccurrences(
            of: "  /\\ \(expectedPredicate)", with: "  /\\ \(wrongPredicate)")
        #expect(wrongModule != module)
        do {
            try verifyRenderedInitialConjunction(wrongModule,
                predicates: predicates.map { $0 == expectedPredicate ? wrongPredicate : $0 },
                expectedIntPredicates: ["second": expectedPredicate])
            Issue.record("A changed generated Init expression was accepted")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "tla.Init")
        }

        let initialIndex = try #require(program.behavior.initializations.firstIndex {
            $0.variable == variable.id
        })
        let prefix = program.behavior.initializations[..<initialIndex]
        let declarations = lines.filter { $0.hasPrefix("__SwiftTLAInitialOverflowFailure\(variable.id.ordinal)") }
        let firstDeclaration = try #require(declarations.first)
        let binders = firstDeclaration.components(separatedBy: "LET ").dropFirst().map {
            String($0.prefix(while: { $0 != " " }))
        }
        let names = Dictionary(uniqueKeysWithValues: zip(prefix.map(\.variable), binders))
        #expect(binders.count == prefix.count)
        let renderer = CompiledTLARenderer(moduleName: program.moduleName,
            reservedNames: [], layout: program.layout,
            bindings: .init(binders: program.binderNames), operators: .init(),
            actions: program.behavior.actions, functions: program.functions,
            enums: program.enums, parameterDomains: program.behavior.parameterDomains)
        let failures = try renderer.expressionEvaluationFailures(resolvedExpression, stateNames: names)
        #expect(failures.count == 2)
        #expect(declarations.count == 2)
        let emitted = try zip(failures, declarations).map { failure, declaration ->
            (failure: RenderedEvaluationFailure, relation: String, operandsName: String?) in
            let separator = try #require(declaration.range(of: " == "))
            let header = String(declaration[..<separator.lowerBound])
            let open = try #require(header.firstIndex(of: "("))
            let close = try #require(header.lastIndex(of: ")"))
            return (failure, String(declaration[separator.upperBound...]),
                String(header[header.index(after: open)..<close]))
        }
        try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(resolvedExpression,
            after: prefix, names: names, emitted: emitted, layout: program.layout)
        var reversedRelations = emitted
        reversedRelations[0].relation = emitted[1].relation
        reversedRelations[1].relation = emitted[0].relation
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verifyInitialAdditionFailures(resolvedExpression,
                after: prefix, names: names, emitted: reversedRelations, layout: program.layout)
        }
    }

    @Test("Generated deterministic Int initialization rejects an early exit before its complete state")
    func deterministicIntInitializationRejectsEarlyExit() throws {
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(
            in: SequentialCopyProofModel.spec.compile()))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SequentialCopyProofModel", program: program))
        let original = try #require(try emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        })
        try emitter.verifyDeterministicIntInitialOutput(original)

        let marker = "var firstFailure: NativeMachineEvaluationError?"
        let wrong = original.description.replacingOccurrences(of: marker, with: """
        \(marker)
        if true { return InitialEvaluationOutcomes(states: [], firstFailure: nil) }
        """)
        #expect(wrong != original.description)
        let declaration = try #require(Parser.parse(source: wrong)
            .statements.first?.item.as(DeclSyntax.self))
        try verifyGeneratedInitialBindings(declaration,
            expected: program.behavior.initializations.map { "let \(emitter.variable($0.variable))" },
            expectedLoops: [:], expectedCandidateSources: [:],
            expectedIntLiterals: Dictionary(uniqueKeysWithValues:
                program.behavior.initializations.compactMap { initialization -> (String, Int)? in
                    guard case .value(let expression) = initialization.initialization,
                          case .value(.integer(let value)) = expression.operation else { return nil }
                    return (emitter.variable(initialization.variable), value)
                }),
            expectedControlLocations: Dictionary(uniqueKeysWithValues:
                program.behavior.initializations.compactMap { initialization -> (String, Int)? in
                    guard case .value(let expression) = initialization.initialization,
                          case .controlLocation(let location) = expression.operation else { return nil }
                    return (emitter.variable(initialization.variable), location.ordinal)
                }))
        try emitter.verifyInitialSelection(declaration, expectedMembershipSources: [:])
        try emitter.verifyInitialStateAssembly(declaration)
        do {
            try emitter.verifyDeterministicIntInitialOutput(declaration)
            Issue.record("An early return discarded the compiled initial state")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "native._initialStates.completeIntOutput")
        }
    }

    @Test("Sequential Do captures every ordered Int read and checked addition")
    func sequentialOrderedIntCapturesRejectStaleReads() throws {
        let specification = OrderedCopyModel.spec
        let source = try #require(specification.sourceAlgorithms.first?.model)
        let lowered = try specification.loweredSourceModel()
        _ = try StraightLineAssignmentCheck.verifySequential(source, lowered: lowered,
            enumerateInitialControl: false)

        func replacingSecondCapture(in action: ActionExpr, with replacement: StateExpr) -> ActionExpr {
            var captures = 0
            func replace(_ action: ActionExpr) -> ActionExpr {
                switch action {
                case .define(let name, let value, let body):
                    captures += 1
                    return .define(name, captures == 2 ? replacement : value, replace(body))
                case .and(let left, let right): return .and(replace(left), replace(right))
                default: return action
                }
            }
            return replace(action)
        }
        var wrongRead = lowered
        wrongRead.actions[0] = NamedAction(name: lowered.actions[0].name,
            body: replacingSecondCapture(in: lowered.actions[0].body, with: .variable("x")))
        #expect(wrongRead.actions[0].body != lowered.actions[0].body)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifySequential(source, lowered: wrongRead,
                enumerateInitialControl: false)
        }

        var wrongAddition = lowered
        wrongAddition.actions[1] = NamedAction(name: lowered.actions[1].name,
            body: replacingSecondCapture(in: lowered.actions[1].body,
                with: .add(.variable("x"), .value(.int(1)))))
        #expect(wrongAddition.actions[1].body != lowered.actions[1].body)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifySequential(source, lowered: wrongAddition,
                enumerateInitialControl: false)
        }
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

    @Test("A set-valued assignment cannot change its emitted target")
    func setAssignmentOutputKeepsTarget() throws {
        let specification = TLASpec(name: "SetAssignmentTarget", variables: [
            .init(name: "items", initialization: .value(.set([.int(0)])),
                generatedSwiftType: "Set<Int>", origin: .source)
        ], actions: [
            NamedAction(name: "replace", body: .assign(.named("items"), .value(.set([.int(1)]))))
        ], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let action = try #require(program.behavior.actions.first)
        let module = try program.renderModule().renderedModuleSource
        let header = "replace == "
        let declaration = try #require(module.split(separator: "\n")
            .first(where: { $0.hasPrefix(header) })?.dropFirst(header.count))
        try StraightLineRenderedActionCheck.verify(action.body, rendered: String(declaration),
            layout: program.layout, binders: program.binderNames)
        let wrongTarget = String(declaration).replacingOccurrences(of: "items' =", with: "other' =")
        #expect(wrongTarget != declaration)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineRenderedActionCheck.verify(action.body, rendered: wrongTarget,
                layout: program.layout, binders: program.binderNames)
        }
    }

    @Test("A set-valued Swift assignment cannot change its compiled literal")
    func setAssignmentSwiftOutputKeepsValue() throws {
        let specification = TLASpec(name: "SetAssignmentValue", variables: [
            .init(name: "items", initialization: .value(.set([.int(0)])),
                generatedSwiftType: "Set<Int>", origin: .source)
        ], actions: [
            NamedAction(name: "replace", body: .assign(.named("items"), .value(.set([.int(1)]))))
        ], invariants: [])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: specification.compile()))
        let action = try #require(program.behavior.actions.first)
        let sourceAction = try #require(specification.actions.first)
        try StraightLineAssignmentCheck.verifyCompiled(sourceAction, bindings: action.bindings,
            body: action.body, layout: program.layout)
        var changedCompiledLiteral = false
        let wrongCompiled = action.body.map { expression in
            guard case .value(.set) = expression.operation else { return expression }
            changedCompiledLiteral = true
            return CompiledExpression(operation: .value(.set([.integer(2)])),
                resultType: expression.resultType, children: expression.children)
        }
        #expect(changedCompiledLiteral)
        #expect(throws: CompilationDiagnostic.self) {
            try StraightLineAssignmentCheck.verifyCompiled(sourceAction, bindings: action.bindings,
                body: wrongCompiled, layout: program.layout)
        }
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SetAssignmentValue", program: program))
        let visitor = try #require(emitter.machineMembers().first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "_visitUpdates0"
        })
        let writes = try emitter.actionFunctions(action.body).writes
        try verifyGeneratedActionWriteOutput(visitor, action: action.body, program: program,
            stateFields: emitter.stateMemberNames, parts: writes)

        let write = try #require(writes.first)
        let replacement = write.value.replacingOccurrences(of: "[1]", with: "[2]")
        #expect(replacement != write.value)
        let wrongSource = visitor.description.replacingOccurrences(
            of: "_Updates(\(write.slot): \(write.value))",
            with: "_Updates(\(write.slot): \(replacement))")
        #expect(wrongSource != visitor.description)
        let wrongVisitor = try #require(Parser.parse(source: wrongSource)
            .statements.first?.item.as(DeclSyntax.self))
        let selfConsistentWrites = writes.map {
            (id: $0.id, slot: $0.slot, value: $0.id == write.id ? replacement : $0.value)
        }
        #expect(throws: CompilationDiagnostic.self) {
            try verifyGeneratedActionWriteOutput(wrongVisitor, action: action.body, program: program,
                stateFields: emitter.stateMemberNames, parts: selfConsistentWrites)
        }
    }
}
