struct VariableID: Hashable, Sendable {
    let ordinal: Int
}

struct BinderID: Hashable, Sendable {
    let ordinal: Int
}

struct ActionID: Hashable, Sendable {
    let ordinal: Int
}

struct CompiledDeclaration: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case variable
        case action
        case invariant
        case temporalProperty
    }

    let kind: Kind
    let name: String
    let sourceOffset: Int?
}

struct CompiledVariableLayout: Hashable, Sendable {
    let id: VariableID
    let declaration: CompiledDeclaration
}

struct CompiledActionLayout: Hashable, Sendable {
    let id: ActionID
    let declaration: CompiledDeclaration
}

struct CompiledLayout: Hashable, Sendable {
    let variables: [CompiledVariableLayout]
    let actions: [CompiledActionLayout]
    let declarations: [CompiledDeclaration]

    init(spec: TLASpec) {
        variables = spec.variables.enumerated().map { ordinal, variable in
            CompiledVariableLayout(
                id: VariableID(ordinal: ordinal),
                declaration: .init(kind: .variable, name: variable.name, sourceOffset: nil)
            )
        }
        actions = spec.actions.enumerated().map { ordinal, action in
            CompiledActionLayout(
                id: ActionID(ordinal: ordinal),
                declaration: .init(kind: .action, name: action.name, sourceOffset: nil)
            )
        }
        declarations = variables.map(\.declaration)
            + actions.map(\.declaration)
            + spec.invariants.map { .init(kind: .invariant, name: $0.name, sourceOffset: nil) }
            + spec.temporalProperties.map {
                .init(kind: .temporalProperty, name: $0.name, sourceOffset: nil)
            }
    }

    func variableID(named name: String) -> VariableID? {
        variables.first { $0.declaration.name == name }?.id
    }

    func actionID(named name: String) -> ActionID? {
        actions.first { $0.declaration.name == name }?.id
    }

    var canonicalEncoding: String {
        declarations.enumerated().map { ordinal, declaration in
            let kind = declaration.kind.rawValue
            let name = declaration.name
            return "\(ordinal):\(kind.utf8.count):\(kind)\(name.utf8.count):\(name)"
        }.joined(separator: "|")
    }
}

enum CompiledReference: Hashable, Sendable {
    case variable(VariableID)
    case binder(BinderID)
    case action(ActionID)
    case symbol(String)
}

struct CompiledBindingTable: Sendable {
    let variables: [String: VariableID]
    let actions: [String: ActionID]
    let references: [String: CompiledReference]

    init(layout: CompiledLayout, references: [String: CompiledReference] = [:]) {
        variables = Dictionary(
            uniqueKeysWithValues: layout.variables.map { ($0.declaration.name, $0.id) }
        )
        actions = Dictionary(
            uniqueKeysWithValues: layout.actions.map { ($0.declaration.name, $0.id) }
        )
        self.references = references
    }
}

struct BindingValidator {
    private let layout: CompiledLayout
    private let closure: FormalModuleClosure
    private var symbols: Set<String>
    private var nextBinderOrdinal = 0
    private var knownBinderNames: Set<String> = []
    private var references: [String: CompiledReference] = [:]

    init(spec: TLASpec, layout: CompiledLayout, closure: FormalModuleClosure) {
        self.layout = layout
        self.closure = closure
        symbols = Set(spec.constants.keys)
            .union(spec.formalParameters.map(\.name))
            .union(spec.formalOperatorDefinitions.map(\.name))
            .union(spec.recursiveFuncs.map(\.name))
            .union(closure.resolvedFormalOperatorDefinitions.map(\.name))
            .union(closure.resolvedRecursiveFuncs.map(\.name))
    }

    mutating func validate(spec: TLASpec) throws -> CompiledBindingTable {
        for (index, variable) in spec.variables.enumerated() {
            let path = "variables.\(variable.name)"
            try validateExpression(variable.initialSet, at: "\(path).initialSet", scope: [:])
            try validateExpression(variable.initExpr, at: "\(path).initExpr", scope: [:])
            try validateExpression(variable.lazySet, at: "\(path).lazySet", scope: [:])
            if layout.variables.indices.contains(index) {
                references["\(path).declaration"] = .variable(layout.variables[index].id)
            }
        }
        for action in spec.actions {
            let scope = try bind(action.bindings.map(\.name), at: "actions.\(action.name).bindings", scope: [:])
            try actionExpression(action.body, at: "actions.\(action.name).body", scope: scope)
        }
        for invariant in spec.invariants {
            try validateExpression(invariant.body, at: "invariants.\(invariant.name).body", scope: [:])
        }
        try validateExpression(spec.constraint, at: "constraint", scope: [:])
        try validateExpression(spec.assume, at: "assume", scope: [:])
        for definition in spec.formalOperatorDefinitions {
            let scope = try bind(definition.parameters.map(\.name), at: "formalOperators.\(definition.name).parameters", scope: [:])
            try validateExpression(definition.body, at: "formalOperators.\(definition.name).body", scope: scope)
        }
        for function in spec.recursiveFuncs {
            let scope = try bind(function.params, at: "recursiveFunctions.\(function.name).parameters", scope: [:])
            try validateExpression(function.body, at: "recursiveFunctions.\(function.name).body", scope: scope)
        }
        let localFormalNames = Set(spec.formalOperatorDefinitions.map(\.name))
        for definition in closure.resolvedFormalOperatorDefinitions where !localFormalNames.contains(definition.name) {
            let scope = try bind(definition.parameters.map(\.name), at: "linkedFormalOperators.\(definition.name).parameters", scope: [:])
            try validateExpression(definition.body, at: "linkedFormalOperators.\(definition.name).body", scope: scope)
        }
        let localRecursiveNames = Set(spec.recursiveFuncs.map(\.name))
        for function in closure.resolvedRecursiveFuncs where !localRecursiveNames.contains(function.name) {
            let scope = try bind(function.params, at: "linkedRecursiveFunctions.\(function.name).parameters", scope: [:])
            try validateExpression(function.body, at: "linkedRecursiveFunctions.\(function.name).body", scope: scope)
        }
        return CompiledBindingTable(layout: layout, references: references)
    }

    private mutating func validateExpression(
        _ expression: StateExpr?,
        at path: String,
        scope: [String: BinderID]
    ) throws {
        guard let expression else { return }
        try validateExpression(expression, at: path, scope: scope)
    }

    private mutating func validateExpression(_ expression: StateExpr, at path: String, scope: [String: BinderID]) throws {
        switch expression {
        case .value:
            return
        case .variable(let name):
            try resolveValue(name, at: path, scope: scope)
        case .enabledAction(let name):
            guard let id = layout.actionID(named: name) else {
                try unresolved(name, at: path, expected: "a declared action")
                return
            }
            references[path] = .action(id)
        case .negate(let value), .not(let value), .cardinality(let value), .powerSet(let value),
             .unionAll(let value), .tupleLength(let value), .tupleHead(let value), .tupleTail(let value),
             .domain(let value), .sequenceFromSet(let value):
            try validateExpression(value, at: path, scope: scope)
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
             .divide(let lhs, let rhs), .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
             .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
             .lessOrEqual(let lhs, let rhs), .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
             .and(let lhs, let rhs), .or(let lhs, let rhs), .in(let lhs, let rhs), .subset(let lhs, let rhs),
             .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
             .tupleDynamicAccess(let lhs, let rhs), .tupleAppend(let lhs, let rhs),
             .tupleConcatenate(let lhs, let rhs), .functionApply(let lhs, let rhs),
             .functionSet(let lhs, let rhs), .setSum(let lhs, let rhs):
            try validateExpression(lhs, at: "\(path).left", scope: scope)
            try validateExpression(rhs, at: "\(path).right", scope: scope)
        case .ifThenElse(let condition, let then, let otherwise):
            try validateExpression(condition, at: "\(path).condition", scope: scope)
            try validateExpression(then, at: "\(path).then", scope: scope)
            try validateExpression(otherwise, at: "\(path).else", scope: scope)
        case .setLiteral(let values), .tupleLiteral(let values):
            for (index, value) in values.enumerated() {
                try validateExpression(value, at: "\(path)[\(index)]", scope: scope)
            }
        case .tupleAccess(let value, _), .recordAccess(let value, _):
            try validateExpression(value, at: path, scope: scope)
        case .recordLiteral(let values):
            for (name, value) in values {
                try validateExpression(value, at: "\(path).\(name)", scope: scope)
            }
        case .except(let function, let key, let value):
            try validateExpression(function, at: "\(path).function", scope: scope)
            try validateExpression(key, at: "\(path).key", scope: scope)
            try validateExpression(value, at: "\(path).value", scope: scope)
        case .caseExpr(let pairs, let otherwise):
            for (index, pair) in pairs.enumerated() {
                try validateExpression(pair, at: "\(path).branch[\(index)]", scope: scope)
            }
            try validateExpression(otherwise, at: "\(path).otherwise", scope: scope)
        case .setFilter(let set, let name, let predicate), .functionLiteral(let set, let name, let predicate),
             .forAll(let set, let name, let predicate), .exists(let set, let name, let predicate),
             .choose(let set, let name, let predicate):
            try validateExpression(set, at: "\(path).domain", scope: scope)
            let bodyScope = try bind([name], at: "\(path).binder", scope: scope)
            try validateExpression(predicate, at: "\(path).body", scope: bodyScope)
        case .setMap(let value, let name, let set):
            try validateExpression(set, at: "\(path).domain", scope: scope)
            let bodyScope = try bind([name], at: "\(path).binder", scope: scope)
            try validateExpression(value, at: "\(path).body", scope: bodyScope)
        case .integerRange(let lower, let upper):
            try validateExpression(lower, at: "\(path).lower", scope: scope)
            try validateExpression(upper, at: "\(path).upper", scope: scope)
        case .foldFunction(let lambda, let initial, let sequence):
            let bodyScope = try bind(lambda.parameters, at: "\(path).parameters", scope: scope)
            try validateExpression(lambda.body, at: "\(path).body", scope: bodyScope)
            try validateExpression(initial, at: "\(path).initial", scope: scope)
            try validateExpression(sequence, at: "\(path).sequence", scope: scope)
        case .operatorApplication(let operation, let arguments):
            try formalOperator(operation, at: "\(path).operator", scope: scope)
            for (index, argument) in arguments.enumerated() {
                switch argument {
                case .value(let value):
                    try validateExpression(value, at: "\(path).arguments[\(index)]", scope: scope)
                case .operator(let formal):
                    try formalOperator(formal, at: "\(path).arguments[\(index)]", scope: scope)
                }
            }
        case .recursiveCall(let name, let arguments):
            guard symbols.contains(name) else {
                throw diagnostic(
                    code: .unresolvedImportedSymbol,
                    path: path,
                    expected: "a linked recursive or formal operator",
                    actual: "unresolved symbol '\(name)'"
                )
            }
            references[path] = .symbol(name)
            for (index, argument) in arguments.enumerated() {
                try validateExpression(argument, at: "\(path).arguments[\(index)]", scope: scope)
            }
        case .letValue(let name, let value, let body):
            try validateExpression(value, at: "\(path).value", scope: scope)
            let bodyScope = try bind([name], at: "\(path).binder", scope: scope)
            try validateExpression(body, at: "\(path).body", scope: bodyScope)
        case .letIn(let operators, let body):
            try validateOperators(operators, body: body, at: path, scope: scope)
        }
    }

    private mutating func formalOperator(_ operation: FormalOperator, at path: String, scope: [String: BinderID]) throws {
        switch operation {
        case .reference(let name, _):
            guard symbols.contains(name) else {
                throw diagnostic(
                    code: .unresolvedImportedSymbol,
                    path: path,
                    expected: "a linked formal operator",
                    actual: "unresolved symbol '\(name)'"
                )
            }
            references[path] = .symbol(name)
        case .lambda(let lambda):
            let bodyScope = try bind(lambda.parameters, at: "\(path).parameters", scope: scope)
            try validateExpression(lambda.body, at: "\(path).body", scope: bodyScope)
        }
    }

    private mutating func validateOperators(
        _ operators: [LocalOperator],
        body: StateExpr,
        at path: String,
        scope: [String: BinderID]
    ) throws {
        try duplicate(operators.map(\.name), at: "\(path).operators")
        let operatorNames = Set(operators.map(\.name))
        let outerSymbols = symbols
        symbols.formUnion(operatorNames)
        defer { symbols = outerSymbols }
        for operation in operators {
            try validateExpression(operation.domain, at: "\(path).\(operation.name).domain", scope: scope)
            let bodyScope = try bind(operation.parameters, at: "\(path).\(operation.name).parameters", scope: scope)
            try validateExpression(operation.body, at: "\(path).\(operation.name).body", scope: bodyScope)
            references["\(path).\(operation.name).declaration"] = .symbol(operation.name)
        }
        for name in operatorNames {
            references["\(path).operators.\(name)"] = .symbol(name)
        }
        try validateExpression(body, at: "\(path).body", scope: scope)
    }

    private mutating func actionExpression(_ action: ActionExpr, at path: String, scope: [String: BinderID]) throws {
        switch action {
        case .assign(let name, let value):
            try assignmentTarget(name, at: "\(path).assign", scope: scope)
            try validateExpression(value, at: "\(path).value", scope: scope)
        case .unchanged(let name):
            try assignmentTarget(name, at: "\(path).unchanged", scope: scope)
        case .guard_(let condition):
            try validateExpression(condition, at: "\(path).guard", scope: scope)
        case .chooseAction(let name, let set):
            try assignmentTarget(name, at: "\(path).choose", scope: scope)
            try validateExpression(set, at: "\(path).set", scope: scope)
        case .existsAction(let name, let set, let body):
            try validateExpression(set, at: "\(path).set", scope: scope)
            let bodyScope = try bind([name], at: "\(path).binder", scope: scope)
            try actionExpression(body, at: "\(path).body", scope: bodyScope)
        case .define(let name, let value, let body):
            try validateExpression(value, at: "\(path).value", scope: scope)
            let bodyScope = try bind([name], at: "\(path).binder", scope: scope)
            try actionExpression(body, at: "\(path).body", scope: bodyScope)
        case .ifElse(let condition, let then, let otherwise):
            try validateExpression(condition, at: "\(path).condition", scope: scope)
            try actionExpression(then, at: "\(path).then", scope: scope)
            try actionExpression(otherwise, at: "\(path).else", scope: scope)
        case .and(let lhs, let rhs), .or(let lhs, let rhs):
            try actionExpression(lhs, at: "\(path).left", scope: scope)
            try actionExpression(rhs, at: "\(path).right", scope: scope)
        }
    }

    private mutating func resolveValue(_ name: String, at path: String, scope: [String: BinderID]) throws {
        if let id = scope[name] {
            references[path] = .binder(id)
            return
        }
        if let id = layout.variableID(named: name) {
            references[path] = .variable(id)
            return
        }
        if symbols.contains(name) {
            references[path] = .symbol(name)
            return
        }
        try unresolved(name, at: path, expected: "a declared variable, scoped binder, or linked symbol")
    }

    private mutating func assignmentTarget(_ name: String, at path: String, scope: [String: BinderID]) throws {
        if scope[name] != nil || knownBinderNames.contains(name) {
            throw diagnostic(
                code: .assignmentToBinder,
                path: path,
                expected: "an assignable declared state variable",
                actual: "binder '\(name)'"
            )
        }
        guard let id = layout.variableID(named: name) else {
            try unresolved(name, at: path, expected: "an assignable declared state variable")
            return
        }
        references[path] = .variable(id)
    }

    private mutating func bind(_ names: [String], at path: String, scope: [String: BinderID]) throws -> [String: BinderID] {
        try duplicate(names, at: path)
        var nested = scope
        for name in names {
            let id = BinderID(ordinal: nextBinderOrdinal)
            nextBinderOrdinal += 1
            knownBinderNames.insert(name)
            nested[name] = id
            references["\(path).\(name)"] = .binder(id)
        }
        return nested
    }

    private func duplicate(_ names: [String], at path: String) throws {
        var seen: Set<String> = []
        for name in names where !seen.insert(name).inserted {
            throw diagnostic(
                code: .duplicateBinder,
                path: "\(path).\(name)",
                expected: "one binder named '\(name)' in this scope",
                actual: "multiple binders named '\(name)'"
            )
        }
    }

    private func unresolved(_ name: String, at path: String, expected: String) throws {
        throw diagnostic(
            code: knownBinderNames.contains(name) ? .outOfScopeReference : .unknownReference,
            path: path,
            expected: expected,
            actual: "unresolved name '\(name)'"
        )
    }

    private func diagnostic(
        code: CompilationDiagnostic.Code,
        path: String,
        expected: String,
        actual: String
    ) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: code,
            stage: .binding,
            path: path,
            expected: expected,
            actual: actual,
            nextSafeAction: "Declare the name in this scope or use a visible declaration, then compile again."
        )
    }
}
