struct VariableID: Hashable, Sendable {
    let ordinal: Int
}

struct BinderID: Hashable, Sendable {
    let ordinal: Int
}

struct ActionID: Hashable, Sendable {
    let ordinal: Int
}

struct ControlLabelID: Hashable, Sendable {
    let ordinal: Int
}

struct OperatorID: Hashable, Sendable {
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

struct CompiledProcedureLayout: Hashable, Sendable {
    let algorithm: String
    let name: String
    let sourceOffset: Int?
}

enum ControlOwner: Hashable, Sendable {
    case sequential(algorithm: String)
    case process(algorithm: String, ordinal: Int, typeName: String)
    case procedure(algorithm: String, name: String)
    case generated(algorithm: String, purpose: String)

    var canonicalEncoding: String {
        switch self {
        case .sequential(let algorithm):
            return "sequential:\(algorithm)"
        case .process(let algorithm, let ordinal, let typeName):
            return "process:\(algorithm):\(ordinal):\(typeName)"
        case .procedure(let algorithm, let name):
            return "procedure:\(algorithm):\(name)"
        case .generated(let algorithm, let purpose):
            return "generated:\(algorithm):\(purpose)"
        }
    }
}

extension ControlOwner {
    var description: ControlOwnerDescription {
        switch self {
        case .sequential(let algorithm):
            return .sequential(algorithm: algorithm)
        case .process(let algorithm, let ordinal, let typeName):
            return .process(
                algorithm: algorithm,
                declarationOrder: ordinal,
                typeName: typeName
            )
        case .procedure(let algorithm, let name):
            return .procedure(algorithm: algorithm, name: name)
        case .generated(let algorithm, let purpose):
            return .generated(algorithm: algorithm, purpose: purpose)
        }
    }
}

struct CompiledControlLabel: Hashable, Sendable {
    let id: ControlLabelID
    let owner: ControlOwner
    let sourceName: String
    let renderedName: String
}

struct CompiledLayout: Hashable, Sendable {
    let variables: [CompiledVariableLayout]
    let actions: [CompiledActionLayout]
    let procedures: [CompiledProcedureLayout]
    let controlLabels: [CompiledControlLabel]
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
        procedures = spec.sourceAlgorithms.flatMap { algorithm in
            algorithm.model.procedures.map { procedure in
                .init(algorithm: algorithm.model.name, name: procedure.name, sourceOffset: nil)
            }
        }
        controlLabels = Self.controlLabels(
            in: spec.sourceAlgorithms,
            actions: spec.actions,
            hasProgramCounter: spec.variables.contains { $0.name == "pc" }
        )
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

    func controlLabelID(owner: ControlOwner, named sourceName: String) -> ControlLabelID? {
        controlLabels.first {
            $0.owner == owner && $0.sourceName == sourceName
        }?.id
    }

    func controlLabel(_ id: ControlLabelID) -> CompiledControlLabel? {
        controlLabels.first { $0.id == id }
    }

    func controlOwner(forActionNamed name: String) -> ControlOwner? {
        let owners = Set(controlLabels.compactMap { label in
            label.sourceName == name || label.renderedName == name ? label.owner : nil
        })
        guard owners.count == 1 else { return nil }
        return owners.first
    }

    func controlLabelID(named name: String, owner: ControlOwner?, algorithm: String?) -> ControlLabelID? {
        if name == "Done" {
            let doneLabels = controlLabels.filter {
                if case .generated(_, "Done") = $0.owner {
                    return $0.sourceName == name
                }
                return false
            }
            if let algorithm {
                return doneLabels.first {
                    $0.owner == .generated(algorithm: algorithm, purpose: "Done")
                }?.id
            }
            if doneLabels.count == 1 {
                return doneLabels.first?.id
            }
        }
        if let owner, let id = controlLabelID(owner: owner, named: name) {
            return id
        }
        let processMatches = controlLabels.filter {
            if case .process = $0.owner {
                return $0.sourceName == name
            }
            return false
        }
        if processMatches.count == 1 {
            return processMatches.first?.id
        }
        let matches = controlLabels.filter {
            $0.sourceName == name || $0.renderedName == name
        }
        guard matches.count == 1 else { return nil }
        return matches.first?.id
    }

    var canonicalEncoding: String {
        let declarationEncoding = declarations.enumerated().map { ordinal, declaration in
            let kind = declaration.kind.rawValue
            let name = declaration.name
            return "\(ordinal):\(kind.utf8.count):\(kind)\(name.utf8.count):\(name)"
        }.joined(separator: "|")
        let controlEncoding = controlLabels.map { label in
            let owner = label.owner.canonicalEncoding
            return "\(label.id.ordinal):\(owner.utf8.count):\(owner)\(label.sourceName.utf8.count):\(label.sourceName)\(label.renderedName.utf8.count):\(label.renderedName)"
        }.joined(separator: "|")
        let procedureEncoding = procedures.map { procedure in
            "\(procedure.algorithm.utf8.count):\(procedure.algorithm)\(procedure.name.utf8.count):\(procedure.name)"
        }.joined(separator: "|")
        return "declarations[\(declarationEncoding)]procedures[\(procedureEncoding)]controls[\(controlEncoding)]"
    }

    private static func controlLabels(
        in algorithms: [Algorithm],
        actions: [NamedAction],
        hasProgramCounter: Bool
    ) -> [CompiledControlLabel] {
        var labels: [CompiledControlLabel] = []

        func append(
            _ steps: [AlgorithmStepModel],
            owner: ControlOwner,
            renderedName: (AlgorithmStepModel) -> String
        ) {
            for step in steps {
                labels.append(
                    .init(
                        id: .init(ordinal: labels.count),
                        owner: owner,
                        sourceName: step.label.name,
                        renderedName: renderedName(step)
                    )
                )
            }
        }

        for algorithm in algorithms {
            let model = algorithm.model
            append(
                model.sequentialSteps,
                owner: .sequential(algorithm: model.name),
                renderedName: { $0.label.name }
            )
            for (ordinal, process) in model.processes.enumerated() {
                append(
                    process.steps,
                    owner: .process(
                        algorithm: model.name,
                        ordinal: ordinal,
                        typeName: process.typeName
                    ),
                    renderedName: { $0.label.name }
                )
            }
            for procedure in model.procedures {
                append(
                    procedure.steps,
                    owner: .procedure(algorithm: model.name, name: procedure.name),
                    renderedName: { "procedure.\(procedure.name).\($0.label.name)" }
                )
            }
            if model.sequentialSteps.isEmpty == false || model.processes.isEmpty == false {
                labels.append(
                    .init(
                        id: .init(ordinal: labels.count),
                        owner: .generated(algorithm: model.name, purpose: "Done"),
                        sourceName: "Done",
                        renderedName: "Done"
                    )
                )
            }
        }
        let knownActionNames = Set(labels.flatMap { [$0.sourceName, $0.renderedName] })
        for action in actions where action.name != "Terminating" && knownActionNames.contains(action.name) == false {
            labels.append(
                .init(
                    id: .init(ordinal: labels.count),
                    owner: .generated(algorithm: algorithms.first?.model.name ?? "", purpose: action.name),
                    sourceName: action.name,
                    renderedName: action.name
                )
            )
        }
        if hasProgramCounter, labels.contains(where: { $0.sourceName == "Done" }) == false {
            labels.append(
                .init(
                    id: .init(ordinal: labels.count),
                    owner: .generated(algorithm: algorithms.first?.model.name ?? "", purpose: "Done"),
                    sourceName: "Done",
                    renderedName: "Done"
                )
            )
        }
        return labels
    }
}

enum CompiledReference: Hashable, Sendable {
    case variable(VariableID)
    case binder(BinderID)
    case action(ActionID)
    case constant(TLAValue)
    case `operator`(OperatorID)
}

struct CompiledBindingTable: Sendable {
    let variables: [String: VariableID]
    let actions: [String: ActionID]
    let operators: [String: OperatorID]
    let references: [String: CompiledReference]

    init(
        layout: CompiledLayout,
        operators: [String: OperatorID] = [:],
        references: [String: CompiledReference] = [:]
    ) {
        variables = Dictionary(
            uniqueKeysWithValues: layout.variables.map { ($0.declaration.name, $0.id) }
        )
        actions = Dictionary(
            uniqueKeysWithValues: layout.actions.map { ($0.declaration.name, $0.id) }
        )
        self.operators = operators
        self.references = references
    }
}

struct BindingValidator {
    private let layout: CompiledLayout
    private let closure: FormalModuleClosure
    private let constants: [String: TLAValue]
    private var operators: [String: OperatorID]
    private var nextBinderOrdinal = 0
    private var nextOperatorOrdinal = 0
    private var knownBinderNames: Set<String> = []
    private var references: [String: CompiledReference] = [:]

    init(spec: TLASpec, layout: CompiledLayout, closure: FormalModuleClosure) {
        self.layout = layout
        self.closure = closure
        constants = spec.constants
        let names = spec.formalOperatorDefinitions.map(\.name)
            + spec.recursiveFuncs.map(\.name)
            + closure.resolvedFormalOperatorDefinitions.map(\.name)
            + closure.resolvedRecursiveFuncs.map(\.name)
        operators = names.reduce(into: [:]) { result, name in
            guard result[name] == nil else { return }
            result[name] = OperatorID(ordinal: result.count)
        }
        nextOperatorOrdinal = operators.count
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
            guard let id = operators[definition.name] else {
                throw diagnostic(code: .unknownReference, path: "formalOperators.\(definition.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["formalOperators.\(definition.name).declaration"] = .operator(id)
            let outerOperators = operators
            let scope = try bindFormalParameters(definition.parameters, at: "formalOperators.\(definition.name).parameters", scope: [:])
            try validateExpression(definition.body, at: "formalOperators.\(definition.name).body", scope: scope)
            operators = outerOperators
        }
        for function in spec.recursiveFuncs {
            guard let id = operators[function.name] else {
                throw diagnostic(code: .unknownReference, path: "recursiveFunctions.\(function.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["recursiveFunctions.\(function.name).declaration"] = .operator(id)
            let scope = try bind(function.params, at: "recursiveFunctions.\(function.name).parameters", scope: [:])
            try validateExpression(function.body, at: "recursiveFunctions.\(function.name).body", scope: scope)
        }
        let localFormalNames = Set(spec.formalOperatorDefinitions.map(\.name))
        for definition in closure.resolvedFormalOperatorDefinitions where !localFormalNames.contains(definition.name) {
            guard let id = operators[definition.name] else {
                throw diagnostic(code: .unknownReference, path: "linkedFormalOperators.\(definition.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["linkedFormalOperators.\(definition.name).declaration"] = .operator(id)
            let outerOperators = operators
            let scope = try bindFormalParameters(definition.parameters, at: "linkedFormalOperators.\(definition.name).parameters", scope: [:])
            try validateExpression(definition.body, at: "linkedFormalOperators.\(definition.name).body", scope: scope)
            operators = outerOperators
        }
        let localRecursiveNames = Set(spec.recursiveFuncs.map(\.name))
        for function in closure.resolvedRecursiveFuncs where !localRecursiveNames.contains(function.name) {
            guard let id = operators[function.name] else {
                throw diagnostic(code: .unknownReference, path: "linkedRecursiveFunctions.\(function.name)", expected: "a declared operator", actual: "no operator identity")
            }
            references["linkedRecursiveFunctions.\(function.name).declaration"] = .operator(id)
            let scope = try bind(function.params, at: "linkedRecursiveFunctions.\(function.name).parameters", scope: [:])
            try validateExpression(function.body, at: "linkedRecursiveFunctions.\(function.name).body", scope: scope)
        }
        return CompiledBindingTable(layout: layout, operators: operators, references: references)
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
            guard let id = operators[name] else {
                throw diagnostic(
                    code: .unresolvedImportedSymbol,
                    path: path,
                    expected: "a linked recursive or formal operator",
                    actual: "unresolved symbol '\(name)'"
                )
            }
            references[path] = .operator(id)
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
            guard let id = operators[name] else {
                throw diagnostic(
                    code: .unresolvedImportedSymbol,
                    path: path,
                    expected: "a linked formal operator",
                    actual: "unresolved symbol '\(name)'"
                )
            }
            references[path] = .operator(id)
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
        let outerOperators = self.operators
        let localOperators = operators.map { operation in
            (operation.name, OperatorID(ordinal: nextOperatorOrdinal))
        }
        nextOperatorOrdinal += localOperators.count
        for local in localOperators {
            self.operators[local.0] = local.1
        }
        defer { self.operators = outerOperators }
        for operation in operators {
            try validateExpression(operation.domain, at: "\(path).\(operation.name).domain", scope: scope)
            let bodyScope = try bind(operation.parameters, at: "\(path).\(operation.name).parameters", scope: scope)
            try validateExpression(operation.body, at: "\(path).\(operation.name).body", scope: bodyScope)
            guard let id = self.operators[operation.name] else {
                throw diagnostic(code: .unknownReference, path: path, expected: "a declared operator", actual: "no operator identity")
            }
            references["\(path).\(operation.name).declaration"] = .operator(id)
        }
        for local in localOperators {
            references["\(path).operators.\(local.0)"] = .operator(local.1)
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
        if let value = constants[name] {
            references[path] = .constant(value)
            return
        }
        if let id = operators[name] {
            references[path] = .operator(id)
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

    private mutating func bindFormalParameters(
        _ parameters: [FormalParameter],
        at path: String,
        scope: [String: BinderID]
    ) throws -> [String: BinderID] {
        try duplicate(parameters.map(\.name), at: path)
        var nested = scope
        for parameter in parameters {
            switch parameter {
            case .value(let name):
                let id = BinderID(ordinal: nextBinderOrdinal)
                nextBinderOrdinal += 1
                knownBinderNames.insert(name)
                nested[name] = id
                references["\(path).\(name)"] = .binder(id)
            case .operator(let name, _):
                let id = OperatorID(ordinal: nextOperatorOrdinal)
                nextOperatorOrdinal += 1
                operators[name] = id
                references["\(path).\(name)"] = .operator(id)
            }
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
