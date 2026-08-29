private enum StateLoweringTask {
    case expression(StateExpr, path: String, scope: BindingScope)
    case build(
        childCount: Int,
        path: String,
        ([LoweredStateExpression]) throws -> LoweredStateExpression
    )
}

private struct LoweredStateExpression {
    let expression: CompiledStateExpr
    let operatorReferences: Set<OperatorID>
}

private enum ActionLoweringTask {
    case expression(ActionExpr, path: String, scope: BindingScope)
    case build(
        childCount: Int,
        path: String,
        ([CompiledActionExpr]) throws -> CompiledActionExpr
    )
}

private struct BindingScope {
    var values: [String: BinderID] = [:]
    var operators: [String: OperatorID] = [:]
}

private enum FormalOperatorLoweringPlan {
    case reference(OperatorID, arity: Int)
    case lambda([BinderID])
}

private enum FormalArgumentLoweringPlan {
    case value
    case `operator`(FormalOperatorLoweringPlan)
}

private struct FormalArgumentBindingPlan {
    let lowering: FormalArgumentLoweringPlan
    let bodyScope: BindingScope?
    let operatorReferences: Set<OperatorID>
}

struct CompiledLowerer {
    let closure: FormalModuleClosure
    let layout: CompiledLayout
    private let constants: [ConstantDecl]
    private let formalParameters: Set<String>
    private let symmetricMembers: [TLAValue]
    private let incomingModuleParameters: [FormalModuleReplacement]
    private let authoredAlgorithm: AlgorithmModel?
    private let reservedRenderedNames: Set<String>
    private let rootOperators: [String: OperatorID]
    private var operatorArities: [OperatorID: Int]
    private var nextBinderOrdinal = 0
    private var nextOperatorOrdinal: Int
    private var binderNames: [BinderID: String] = [:]
    private var knownBinderNames: Set<String> = []
    private var operatorNames: [OperatorID: String]
    private var boundedLocalOperators: Set<OperatorID> = []

    init(
        spec: TLASpec,
        closure: FormalModuleClosure,
        layout: CompiledLayout,
        incomingModuleParameters: [FormalModuleReplacement] = []
    ) {
        self.closure = closure
        self.layout = layout
        constants = spec.constants
        formalParameters = Set(spec.formalParameters.map(\.name))
        symmetricMembers = spec.symmetricCollections.flatMap(\.metadata.members)
        self.incomingModuleParameters = incomingModuleParameters
        authoredAlgorithm = spec.sourceAlgorithms.first?.model
        var renderedNames = spec.renderedDeclarationNames()
        renderedNames.formUnion(spec.symmetricCollections.flatMap(\.metadata.generatedSymbols))
        renderedNames.formUnion(spec.symmetrySets.map { "Symm\($0.variableName)" })
        renderedNames.formUnion(incomingModuleParameters.map(\.operatorName))
        reservedRenderedNames = renderedNames
        let signatures = spec.formalOperatorDefinitions.map { ($0.name, $0.parameters.count) }
            + spec.recursiveFuncs.map { ($0.name, $0.params.count) }
            + closure.linkedOperators.formalOperatorDefinitions.map { ($0.name, $0.parameters.count) }
            + closure.linkedOperators.recursiveFunctions.map { ($0.name, $0.params.count) }
        var operators: [String: OperatorID] = [:]
        var arities: [OperatorID: Int] = [:]
        for (name, arity) in signatures where operators[name] == nil {
            let id = OperatorID(ordinal: operators.count)
            operators[name] = id
            arities[id] = arity
        }
        operatorArities = arities
        rootOperators = operators
        operatorNames = Dictionary(uniqueKeysWithValues: operators.map { ($0.value, $0.key) })
        nextOperatorOrdinal = operators.count
    }

    var bindings: CompiledBindingTable {
        .init(operatorNames: operatorNames, binders: binderNames)
    }

    private var rootScope: BindingScope {
        .init(operators: rootOperators)
    }

    mutating func lower(spec: TLASpec) throws -> CompiledSemantics {
        for constant in spec.constants {
            try validateValue(constant.value, at: "constants.\(constant.name)")
        }
        guard spec.variables.count == layout.variables.count,
              spec.actions.count == layout.actions.count,
              spec.invariants.count == layout.stateProperties.count,
              spec.temporalProperties.count == layout.temporalProperties.count
        else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .lowering,
                path: "layout.declarations",
                expected: "layout counts matching variables \(spec.variables.count), actions \(spec.actions.count), invariants \(spec.invariants.count), and temporal properties \(spec.temporalProperties.count)",
                actual: "variables \(layout.variables.count), actions \(layout.actions.count), invariants \(layout.stateProperties.count), and temporal properties \(layout.temporalProperties.count)",
                nextSafeAction: "Compile the model again from its current source."
            )
        }
        var initializations: [VariableID: CompiledVariableInitialization] = [:]
        for (declaration, variableLayout) in zip(spec.variables, layout.variables) {
            let path = "variables.\(declaration.name)"
            if case .value(let value) = declaration.initialization,
               spec.symmetricCollections.contains(where: { $0.name == declaration.name }) == false {
                try validateValue(value, at: "\(path).initialization")
            }
            initializations[variableLayout.id] = try lower(
                declaration.initialization,
                at: "\(path).initialization",
                scope: rootScope
            )
        }
        let actions: [CompiledAction] = try zip(spec.actions, layout.actions).map {
            try lower($0.0, id: $0.1.id)
        }
        let actionsByID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        let invariants: [CompiledInvariant] = try zip(spec.invariants, layout.stateProperties).map {
            CompiledInvariant(
                id: $0.1.id,
                name: $0.0.name,
                body: try lower($0.0.body, at: "invariants.\($0.0.name).body", scope: rootScope)
            )
        }
        let temporalProperties = try zip(spec.temporalProperties, layout.temporalProperties).map {
            CompiledTemporal(
                id: $0.1.id,
                name: $0.0.name,
                expression: try lower(
                    $0.0.expr,
                    at: "temporalProperties.\($0.0.name)",
                    scope: rootScope
                )
            )
        }
        let fairness = try spec.fairness.enumerated().map { offset, condition in
            try lower(condition, actions: actionsByID, at: "fairness[\(offset)]")
        }
        let formalOperators: [CompiledFormalOperatorDefinition] = try spec.formalOperatorDefinitions.map { definition in
            let path = "formalOperators.\(definition.name)"
            if let issue = definition.sourceIssue {
                throw issue.compilationDiagnostic(stage: .binding, path: path)
            }
            guard let id = rootScope.operators[definition.name] else { throw diagnostic(path: path) }
            let scope = try bind(definition.parameters, at: "\(path).parameters", scope: rootScope)
            return CompiledFormalOperatorDefinition(
                id: id,
                parameters: try compiledParameters(definition.parameters, scope: scope, at: "\(path).parameters"),
                body: try lower(definition.body, at: "\(path).body", scope: scope)
            )
        }
        let recursiveFunctions: [CompiledRecursiveFunction] = try spec.recursiveFuncs.map { function in
            let path = "recursiveFunctions.\(function.name)"
            guard let id = rootScope.operators[function.name] else { throw diagnostic(path: path) }
            let scope = try bind(function.params, at: "\(path).parameters", scope: rootScope)
            return CompiledRecursiveFunction(
                id: id,
                parameters: try function.params.map { try bound($0, in: scope, at: "\(path).parameters") },
                body: try lower(function.body, at: "\(path).body", scope: scope)
            )
        }
        let formalModuleReplacements = try spec.importConfigurations.flatMap { configuration in
            try configuration.replacements.map { replacement in
                CompiledFormalModuleReplacement(
                    moduleName: configuration.moduleName,
                    operatorName: replacement.operatorName,
                    definitionName: replacement.definitionName,
                    expression: try lower(
                        replacement.expression,
                        at: "importConfigurations.\(configuration.moduleName).\(replacement.operatorName)",
                        scope: rootScope
                    )
                )
            }
        }
        let moduleInstances = try spec.moduleInstances.enumerated().map { offset, instance in
            guard let id = layout.moduleInstanceID(named: instance.name) else {
                throw diagnostic(path: "moduleInstances[\(offset)].declaration")
            }
            let arguments = try spec.instanceArguments(for: instance).enumerated().map { argumentOffset, argument in
                CompiledModuleArgument(
                    parameter: argument.parameter,
                    value: try lower(
                        argument.value,
                        at: "moduleInstances[\(offset)].arguments[\(argumentOffset)]",
                        scope: rootScope
                    )
                )
            }
            return CompiledModuleInstance(id: id, arguments: arguments)
        }
        let localFormalNames = Set(spec.formalOperatorDefinitions.map(\.name))
        let linkedFormalOperators = try closure.linkedOperators.formalOperatorDefinitions
            .filter { !localFormalNames.contains($0.name) }
            .map { definition in
                let path = "linkedFormalOperators.\(definition.name)"
                if let issue = definition.sourceIssue {
                    throw issue.compilationDiagnostic(stage: .binding, path: path)
                }
                guard let id = rootScope.operators[definition.name] else { throw diagnostic(path: path) }
                let scope = try bind(definition.parameters, at: "\(path).parameters", scope: rootScope)
                return CompiledFormalOperatorDefinition(
                    id: id,
                    parameters: try compiledParameters(definition.parameters, scope: scope, at: "\(path).parameters"),
                    body: try lower(definition.body, at: "\(path).body", scope: scope)
                )
            }
        let localRecursiveNames = Set(spec.recursiveFuncs.map(\.name))
        let linkedRecursiveFunctions = try closure.linkedOperators.recursiveFunctions
            .filter { !localRecursiveNames.contains($0.name) }
            .map { function in
                let path = "linkedRecursiveFunctions.\(function.name)"
                guard let id = rootScope.operators[function.name] else { throw diagnostic(path: path) }
                let scope = try bind(function.params, at: "\(path).parameters", scope: rootScope)
                return CompiledRecursiveFunction(
                    id: id,
                    parameters: try function.params.map { try bound($0, in: scope, at: "\(path).parameters") },
                    body: try lower(function.body, at: "\(path).body", scope: scope)
                )
            }
        let allFormalOperators = formalOperators + linkedFormalOperators
        let allRecursiveFunctions = recursiveFunctions + linkedRecursiveFunctions
        let assume = try lowerOptional(spec.assume, at: "assume", scope: rootScope)
        if let assume {
            let requirements = assume.stateRequirements(
                formalOperators: allFormalOperators,
                recursiveFunctions: allRecursiveFunctions
            )
            guard requirements.variables.isEmpty && requirements.requiresCompleteState == false else {
                throw CompilationDiagnostic(
                    code: .stateDependentAssumption,
                    stage: .lowering,
                    path: "assume",
                    expected: "a state-independent module assumption",
                    actual: requirements.requiresCompleteState
                        ? "an assumption that evaluates action enabledness"
                        : "an assumption that reads model state",
                    nextSafeAction: "Express state rules as invariants or temporal properties."
                )
            }
        }
        let orderedInitializations = try orderedInitializations(
            initializations,
            formalOperators: allFormalOperators,
            recursiveFunctions: allRecursiveFunctions
        )
        return CompiledSemantics(
            checkDeadlock: spec.checkDeadlock,
            variableInitializations: orderedInitializations,
            actions: actions,
            invariants: invariants,
            temporalProperties: temporalProperties,
            fairness: fairness,
            constraint: try lowerOptional(spec.constraint, at: "constraint", scope: rootScope),
            assume: assume,
            formalOperatorDefinitions: allFormalOperators,
            recursiveFunctions: allRecursiveFunctions,
            formalModuleReplacements: formalModuleReplacements,
            moduleInstances: moduleInstances,
            symmetrySets: spec.symmetrySets.map { symmetry in
                .init(values: symmetry.values)
            },
            symmetricCollections: try spec.symmetricCollections.map { collection in
                .init(
                    variable: try variable(named: collection.name, at: "variables.\(collection.name).declaration"),
                    members: collection.metadata.members,
                    domainSymbol: collection.metadata.domainSymbol,
                    initial: .init(formal: collection.metadata.initial)
                )
            }
        )
    }

    mutating func refinementExpression(_ expression: StateExpr, at path: String) throws -> CompiledStateExpr {
        try lower(expression, at: path, scope: rootScope)
    }

    mutating func authoredPlusCalPlan(
        _ plan: AuthoredPlusCalAlgorithmPlan
    ) throws -> CompiledAuthoredPlusCalAlgorithmPlan {
        guard let authoredAlgorithm else { throw diagnostic(path: "authoredPlusCal") }
        guard plan.procedures.count == layout.procedures.count else {
            throw CompilationDiagnostic(
                code: .compilationIdentityMismatch,
                stage: .lowering,
                path: "authoredPlusCal.procedures",
                expected: "\(plan.procedures.count) compiled procedure identities",
                actual: "\(layout.procedures.count) layout procedure identities",
                nextSafeAction: "Compile the model again from its current source."
            )
        }
        let propertyPlan = try authoredPlusCalProperties(in: authoredAlgorithm)
        return .init(
            name: plan.name,
            sequentialFairness: plan.sequentialFairness,
            shared: try plan.shared.enumerated().map {
                try authoredPlusCalState(
                    $0.element,
                    at: "authoredPlusCal.shared[\($0.offset)]",
                    scope: rootScope
                )
            },
            procedures: try zip(plan.procedures, layout.procedures).enumerated().map { index, value in
                let procedure = value.0
                let path = "authoredPlusCal.procedures[\(index)]"
                let scope = try bind(procedure.parameters.map(\.root), at: "\(path).parameters", scope: rootScope)
                return .init(
                    id: value.1.id,
                    parameters: try procedure.parameters.map {
                        try bound($0.root, in: scope, at: "\(path).parameters")
                    },
                    locals: try procedure.locals.enumerated().map {
                        try authoredPlusCalState($0.element, at: "\(path).locals[\($0.offset)]", scope: scope)
                    },
                    steps: try procedure.steps.enumerated().map {
                        try authoredPlusCalStep(
                            $0.element,
                            owner: .procedure(algorithm: plan.name, name: procedure.name),
                            at: "\(path).steps[\($0.offset)]",
                            scope: scope
                        )
                    }
                )
            },
            processes: try plan.processes.enumerated().map { index, process in
                let path = "authoredPlusCal.processes[\(index)]"
                var scope = rootScope
                scope.values["self"] = try allocateBinder(
                    "self",
                    renderedName: "self",
                    in: scope,
                    at: "\(path).binders"
                )
                return .init(
                    name: process.name,
                    domain: process.domain,
                    fairness: process.fairness,
                    locals: try process.locals.enumerated().map {
                        try authoredPlusCalState($0.element, at: "\(path).locals[\($0.offset)]", scope: scope)
                    },
                    steps: try process.steps.enumerated().map {
                        try authoredPlusCalStep(
                            $0.element,
                            owner: process.owner,
                            at: "\(path).steps[\($0.offset)]",
                            scope: scope
                        )
                    }
                )
            },
            sequentialSteps: try plan.sequentialSteps.enumerated().map {
                try authoredPlusCalStep(
                    $0.element,
                    owner: .sequential(algorithm: plan.name),
                    at: "authoredPlusCal.sequentialSteps[\($0.offset)]",
                    scope: rootScope
                )
            },
            properties: propertyPlan.properties,
            translatorOwnedPropertyNames: propertyPlan.translatorOwnedNames
        )
    }

    private func authoredPlusCalProperties(
        in algorithm: AlgorithmModel
    ) throws -> (properties: [CompiledAuthoredPlusCalProperty], translatorOwnedNames: Set<String>) {
        func isTranslatorTermination(_ temporal: NamedTemporal) -> Bool {
            guard temporal.name == "Termination", algorithm.processes.count == 1,
                  case .eventually(let expression) = temporal.expr,
                  case .forAll(let domain, let binding, let predicate) = expression,
                  domain == .setLiteral(algorithm.processes[0].domain.map(StateExpr.value))
            else { return false }
            switch predicate {
            case .equal(.functionApply(.programCounter, .variable(let process)), .controlLocation(let location)),
                 .equal(.controlLocation(let location), .functionApply(.programCounter, .variable(let process))):
                return location.sourceName == CompilerControlSymbol.done.rawValue && process == binding
            default:
                return false
            }
        }

        func propertyID(
            kind: CompiledDeclaration.Kind,
            named name: String,
            at path: String
        ) throws -> PropertyID {
            let properties = kind == .invariant ? layout.stateProperties : layout.temporalProperties
            guard let property = properties.first(where: { $0.declaration.name == name }) else {
                throw diagnostic(path: path, actual: "unresolved property '\(name)'")
            }
            return property.id
        }

        func collect(
            _ components: [AlgorithmComponentModel],
            path: String
        ) throws -> (properties: [CompiledAuthoredPlusCalProperty], translatorOwnedNames: Set<String>) {
            var properties: [CompiledAuthoredPlusCalProperty] = []
            var translatorOwnedNames: Set<String> = []
            for (index, component) in components.enumerated() {
                let componentPath = "\(path)[\(index)]"
                switch component {
                case .invariant(let invariant):
                    properties.append(.invariant(
                        id: try propertyID(kind: .invariant, named: invariant.name, at: componentPath),
                        name: invariant.name
                    ))
                case .temporal(let temporal):
                    if isTranslatorTermination(temporal) {
                        translatorOwnedNames.insert(temporal.name)
                    } else if temporal.name == "Termination" {
                        throw CompilationDiagnostic(
                            code: .duplicateRenderedModuleDefinition,
                            stage: .rendering,
                            path: componentPath,
                            expected: "the translator's standard Termination predicate for this process family",
                            actual: "a distinct property named Termination",
                            nextSafeAction: "Give the property a distinct name, or declare the standard process termination property."
                        )
                    } else {
                        properties.append(.temporal(
                            id: try propertyID(kind: .temporalProperty, named: temporal.name, at: componentPath),
                            name: temporal.name
                        ))
                    }
                case .process(let process):
                    let nested = try collect(process.components, path: "\(componentPath).components")
                    properties += nested.properties
                    translatorOwnedNames.formUnion(nested.translatorOwnedNames)
                case .shared, .procedure, .formalOperator, .stateConstraint, .invalidPlacement, .local, .step:
                    continue
                }
            }
            return (properties, translatorOwnedNames)
        }

        return try collect(algorithm.components, path: "components")
    }

    private mutating func authoredPlusCalState(
        _ declaration: AlgorithmStateModel,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledAuthoredPlusCalState {
        let initialization: CompiledAuthoredPlusCalState.Initialization
        switch declaration.initialization {
        case .value(let value): initialization = .value(value)
        case .expression(let expression):
            initialization = .expression(try lower(expression, at: "\(path).initialization", scope: scope))
        case .memberOf(let expression):
            initialization = .memberOf(try lower(expression, at: "\(path).initialization", scope: scope))
        }
        return .init(
            variable: try variable(named: declaration.root, at: "\(path).declaration"),
            initialization: initialization
        )
    }

    private mutating func authoredPlusCalStep(
        _ step: AlgorithmStepModel,
        owner: ControlOwner,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledAuthoredPlusCalStep {
        .init(
            label: try controlLocation(.init(step.label.name), owner: owner, at: "\(path).label"),
            statements: try authoredPlusCalStatements(
                step.statements,
                owner: owner,
                at: "\(path).statements",
                scope: scope
            ),
            loopCondition: try lowerOptional(step.loopCondition, at: "\(path).condition", scope: scope)
        )
    }

    private mutating func authoredPlusCalStatements(
        _ statements: [AlgorithmStatementModel],
        owner: ControlOwner,
        at path: String,
        scope: BindingScope
    ) throws -> [CompiledAuthoredPlusCalStatement] {
        try statements.enumerated().map { index, statement in
            let statementPath = "\(path)[\(index)]"
            switch statement {
            case .rejected(let diagnostic):
                throw invalidAuthoredPlusCalStatement(diagnostic.rawValue, at: statementPath)
            case .await(let expression):
                return .await(try lower(expression, at: "\(statementPath).condition", scope: scope))
            case .assert(let expression):
                return .assert(try lower(expression, at: "\(statementPath).condition", scope: scope))
            case .set(let target, let value):
                return .set(
                    target: try authoredPlusCalLValue(target, at: "\(statementPath).target", scope: scope),
                    value: try lower(value, at: "\(statementPath).value", scope: scope)
                )
            case .parallel(let assignments):
                return .parallel(try assignments.enumerated().map { assignmentIndex, assignment in
                    let assignmentPath = "\(statementPath)[\(assignmentIndex)]"
                    return .init(
                        target: try authoredPlusCalLValue(assignment.target, at: "\(assignmentPath).target", scope: scope),
                        value: try lower(assignment.value, at: "\(assignmentPath).value", scope: scope)
                    )
                })
            case .letBinding(let variable, let value, let body):
                let nested = try bind([variable], at: "\(statementPath).binder", scope: scope)
                return .letBinding(
                    variable: try bound(variable, in: nested, at: "\(statementPath).binder"),
                    value: try lower(value, at: "\(statementPath).value", scope: scope),
                    try authoredPlusCalStatements(body, owner: owner, at: "\(statementPath).body", scope: nested)
                )
            case .with(let variable, let source, let body):
                let nested = try bind([variable], at: "\(statementPath).binder", scope: scope)
                return .with(
                    variable: try bound(variable, in: nested, at: "\(statementPath).binder"),
                    source: try lower(source, at: "\(statementPath).source", scope: scope),
                    try authoredPlusCalStatements(body, owner: owner, at: "\(statementPath).body", scope: nested)
                )
            case .ifElse(let condition, let then, let otherwise):
                return .ifElse(
                    try lower(condition, at: "\(statementPath).condition", scope: scope),
                    try authoredPlusCalStatements(then, owner: owner, at: "\(statementPath).then", scope: scope),
                    try authoredPlusCalStatements(otherwise, owner: owner, at: "\(statementPath).else", scope: scope)
                )
            case .either(let first, let second):
                return .either(
                    try authoredPlusCalStatements(first, owner: owner, at: "\(statementPath).first", scope: scope),
                    try authoredPlusCalStatements(second, owner: owner, at: "\(statementPath).second", scope: scope)
                )
            case .choose:
                throw invalidAuthoredPlusCalStatement("choose", at: statementPath)
            case .goto(let label):
                return .goto(try controlLocation(.init(label.name), owner: owner, at: "\(statementPath).label"))
            case .call(let target, let arguments):
                guard let procedure = layout.procedures.first(where: { $0.name == target })?.id else {
                    throw diagnostic(path: "\(statementPath).procedure")
                }
                return .call(
                    target: procedure,
                    arguments: try arguments.enumerated().map {
                        try lower($0.element, at: "\(statementPath).arguments[\($0.offset)]", scope: scope)
                    }
                )
            case .return: return .return
            case .stop: throw invalidAuthoredPlusCalStatement("stop", at: statementPath)
            case .skip: return .skip
            }
        }
    }

    private mutating func authoredPlusCalLValue(
        _ target: AlgorithmLValueModel,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledAuthoredPlusCalLValue {
        switch target {
        case .root(let name): return .root(try variable(named: name, at: "\(path).root"))
        case .function(let name, let key):
            return .function(
                root: try variable(named: name, at: "\(path).root"),
                key: try lower(key, at: "\(path).key", scope: scope)
            )
        }
    }

    private func invalidAuthoredPlusCalStatement(
        _ statement: String,
        at path: String
    ) -> CompilationDiagnostic {
        .init(
            code: .invalidAuthoredPlusCalPlan,
            stage: .lowering,
            path: path,
            expected: "a projected authored PlusCal statement",
            actual: statement,
            nextSafeAction: "Compile the model from its current source."
        )
    }

    private func orderedInitializations(
        _ initializations: [VariableID: CompiledVariableInitialization],
        formalOperators: [CompiledFormalOperatorDefinition],
        recursiveFunctions: [CompiledRecursiveFunction]
    ) throws -> [(variable: VariableID, initialization: CompiledVariableInitialization)] {
        let declarationOrder = layout.variables.map(\.id)
        let declared = Set(declarationOrder)
        var dependencies: [VariableID: Set<VariableID>] = [:]
        for variable in declarationOrder {
            let analysis: (variables: Set<VariableID>, requiresCompleteState: Bool)
            switch initializations[variable] {
            case .value:
                analysis = ([], false)
            case .expression(let expression), .memberOf(let expression):
                analysis = expression.stateRequirements(
                    formalOperators: formalOperators,
                    recursiveFunctions: recursiveFunctions
                )
            case nil:
                let name = layout.variables.first { $0.id == variable }?.declaration.name ?? "unknown"
                throw CompilationDiagnostic(
                    code: .missingVariableInitializer,
                    stage: .lowering,
                    path: "variables.\(name).initialization",
                    expected: "one typed variable initializer",
                    actual: "no initializer was lowered",
                    nextSafeAction: "Declare one fixed, expression, or finite-domain initializer."
                )
            }
            if analysis.requiresCompleteState {
                let name = layout.variables.first { $0.id == variable }?.declaration.name ?? "unknown"
                throw CompilationDiagnostic(
                    code: .actionEnablednessInInitializer,
                    stage: .lowering,
                    path: "variables.\(name).initialization",
                    expected: "an initializer that can be evaluated before a complete state exists",
                    actual: "the initializer evaluates action enabledness",
                    nextSafeAction: "Initialize the variable from values and previously initialized variables."
                )
            }
            dependencies[variable] = analysis.variables.intersection(declared)
        }
        var ordered: [(variable: VariableID, initialization: CompiledVariableInitialization)] = []
        var remaining = Set(declarationOrder)
        while remaining.isEmpty == false {
            guard let next = declarationOrder.first(where: {
                remaining.contains($0) && dependencies[$0, default: []].isDisjoint(with: remaining)
            }) else {
                var path: [VariableID] = []
                var positions: [VariableID: Int] = [:]
                var current = declarationOrder.first(where: remaining.contains)
                var cycle: [VariableID] = []
                while let variable = current {
                    if let start = positions[variable] {
                        cycle = Array(path[start...]) + [variable]
                        break
                    }
                    positions[variable] = path.count
                    path.append(variable)
                    current = declarationOrder.first {
                        remaining.contains($0) && dependencies[variable, default: []].contains($0)
                    }
                }
                let names = cycle.compactMap { variable in
                    layout.variables.first { $0.id == variable }?.declaration.name
                }
                throw CompilationDiagnostic(
                    code: .cyclicVariableInitialization,
                    stage: .lowering,
                    path: "variables.\(names.first ?? "unknown").initialization",
                    expected: "an acyclic variable-initialization dependency graph",
                    actual: "dependency cycle \(names.joined(separator: " -> "))",
                    nextSafeAction: "Break the cycle so each initial value depends only on independently initialized variables."
                )
            }
            guard let initialization = initializations[next] else {
                let name = layout.variables.first { $0.id == next }?.declaration.name ?? "unknown"
                throw CompilationDiagnostic(
                    code: .missingVariableInitializer,
                    stage: .lowering,
                    path: "variables.\(name).initialization",
                    expected: "one typed variable initializer",
                    actual: "the ordered declaration has no initializer",
                    nextSafeAction: "Declare one fixed, expression, or finite-domain initializer."
                )
            }
            ordered.append((next, initialization))
            remaining.remove(next)
            dependencies.removeValue(forKey: next)
        }
        return ordered
    }

    private func lower(
        _ condition: FairnessCondition,
        actions: [ActionID: CompiledAction],
        at path: String
    ) throws -> CompiledFairnessCondition {
        let action: ActionID
        let arguments: [TLAValue]?
        switch condition {
        case .weakFairnessNext:
            return .init(scope: .next, isStrong: false)
        case .strongFairnessNext:
            return .init(scope: .next, isStrong: true)
        case .weakFairness(let name):
            action = try self.action(named: name, at: "\(path).action")
            arguments = nil
        case .strongFairness(let name):
            action = try self.action(named: name, at: "\(path).action")
            arguments = nil
        case .weakFairnessActionCall(let value), .strongFairnessActionCall(let value):
            action = try self.action(named: value.name, at: "\(path).action")
            arguments = value.arguments
            for (index, argument) in value.arguments.enumerated() {
                try validateValue(argument, at: "\(path).arguments[\(index)]")
            }
        }
        guard let declaration = layout.actions.first(where: { $0.id == action }),
              let compiled = actions[action]
        else { throw diagnostic(path: path) }
        if let arguments, accepts(arguments, for: compiled) == false {
            throw CompilationDiagnostic(
                code: .unknownReference,
                stage: .lowering,
                path: path,
                expected: "a declared finite action call",
                actual: "fairness references '\(formalActionCall(named: declaration.declaration.name, arguments: arguments))'",
                nextSafeAction: "Use an action call declared by the source model."
            )
        }
        let scope: CompiledFairnessCondition.Scope
        if let arguments {
            scope = .actionCall(.init(action: action, arguments: arguments))
        } else {
            scope = .action(action)
        }
        return .init(scope: scope, isStrong: condition.isStrong)
    }

    private mutating func lower(_ action: NamedAction, id: ActionID) throws -> CompiledAction {
        if let issue = action.sourceIssue {
            throw issue.compilationDiagnostic(stage: .binding, path: "actions.\(action.name).bindings")
        }
        var scope = rootScope
        let bindings = try action.bindings.map {
            for (index, value) in $0.values.enumerated() {
                try validateValue(value, at: "actions.\(action.name).bindings.\($0.name)[\(index)]")
            }
            let binder = try allocateBinder(
                $0.name,
                in: scope,
                at: "actions.\(action.name).bindings.\($0.name)"
            )
            scope.values[$0.name] = binder
            return CompiledActionBinding(
                binder: binder,
                sourceName: $0.name,
                values: $0.values,
                generatedSwiftType: $0.generatedSwiftType
            )
        }
        let body = try lower(action.body, at: "actions.\(action.name).body", scope: scope)
        if bindings.isEmpty,
           case .existsAction(let sourceMember, _, _) = action.body,
           case .existsAction(let member, .domain(.stateVariable(let variable)), let memberBody) = body,
           layout.variables.indices.contains(variable.ordinal),
           let collection = layout.variables[variable.ordinal].symmetricCollection {
            return CompiledAction(
                id: id,
                bindings: [CompiledActionBinding(
                    binder: member,
                    sourceName: sourceMember,
                    values: collection.members,
                    generatedSwiftType: collection.elementType.map { "\($0).ID" }
                )],
                body: memberBody,
                symmetricCollection: variable
            )
        }
        return CompiledAction(
            id: id,
            bindings: bindings,
            body: body,
            symmetricCollection: nil
        )
    }

    private func accepts(_ arguments: [TLAValue], for action: CompiledAction) -> Bool {
        arguments.count == action.bindings.count
            && zip(arguments, action.bindings).allSatisfy { argument, binding in
                binding.values.contains(argument)
            }
    }

    private mutating func lowerOptional(
        _ expression: StateExpr?,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledStateExpr? {
        guard let expression else { return nil }
        return try lower(expression, at: path, scope: scope)
    }

    private mutating func lower(
        _ expression: StateExpr,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledStateExpr {
        try lowerWithReferences(expression, at: path, scope: scope).expression
    }

    private mutating func lowerWithReferences(
        _ expression: StateExpr,
        at path: String,
        scope: BindingScope
    ) throws -> (expression: CompiledStateExpr, operatorReferences: Set<OperatorID>) {
        var tasks = [StateLoweringTask.expression(expression, path: path, scope: scope)]
        var lowered: [LoweredStateExpression] = []
        while let task = tasks.popLast() {
            switch task {
            case .expression(let expression, let path, let scope):
                switch expression {
                case .sourceIssue(let issue): throw issue.compilationDiagnostic(stage: .lowering, path: path)
                case .value(let value):
                    try validateValue(value, at: path)
                    lowered.append(.init(expression: .value(value), operatorReferences: []))
                case .currentProcess:
                    throw CompilationDiagnostic(
                        code: .unknownReference,
                        stage: .binding,
                        path: path,
                        expected: "a process scope",
                        actual: "current-process identity outside an algorithm process",
                        nextSafeAction: "Use current-process identity inside an algorithm process."
                    )
                case .processLocalFamily(let name):
                    throw CompilationDiagnostic(
                        code: .unknownReference,
                        stage: .binding,
                        path: path,
                        expected: "a process-local declaration lowered from an algorithm",
                        actual: "process-local family '\(name)' outside algorithm lowering",
                        nextSafeAction: "Use process-local state inside its declaring algorithm process."
                    )
                case .programCounter:
                    guard let variable = layout.programCounterID() else { throw diagnostic(path: path) }
                    lowered.append(.init(expression: .stateVariable(variable), operatorReferences: []))
                case .procedureStack:
                    guard let variable = layout.procedureStackID() else { throw diagnostic(path: path) }
                    lowered.append(.init(expression: .stateVariable(variable), operatorReferences: []))
                case .variable(let name):
                    let expression = try value(named: name, scope: scope, at: path)
                    let references: Set<OperatorID>
                    if case .operatorReference(let operation) = expression { references = [operation] }
                    else { references = [] }
                    lowered.append(.init(expression: expression, operatorReferences: references))
                case .controlLocation(let reference):
                    let matches = layout.controlLocations.filter { location in
                        location.sourceName == reference.sourceName
                            && (reference.owner.map { $0 == location.owner } ?? true)
                    }
                    guard matches.count == 1, let location = matches.first?.id else {
                        throw CompilationDiagnostic(
                            code: .unknownControlLocation,
                            stage: .binding,
                            path: path,
                            expected: "a control location declared by the source algorithm",
                            actual: "unresolved control location '\(reference.sourceName)'",
                            nextSafeAction: "Use a control location declared in the same algorithm scope."
                        )
                    }
                    lowered.append(.init(expression: .controlLocation(location), operatorReferences: []))
                case .enabledAction(let name):
                    lowered.append(.init(
                        expression: .enabledAction(try action(named: name, at: path)),
                        operatorReferences: []
                    ))
                case .negate(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.negate, on: &tasks)
                case .not(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.not, on: &tasks)
                case .cardinality(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.cardinality, on: &tasks)
                case .powerSet(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.powerSet, on: &tasks)
                case .unionAll(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.unionAll, on: &tasks)
                case .tupleLength(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.tupleLength, on: &tasks)
                case .tupleHead(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.tupleHead, on: &tasks)
                case .tupleTail(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.tupleTail, on: &tasks)
                case .domain(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.domain, on: &tasks)
                case .sequenceFromSet(let value): scheduleUnary(value, at: path, scope: scope, build: CompiledStateExpr.sequenceFromSet, on: &tasks)
                case .add(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.add, on: &tasks)
                case .subtract(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.subtract, on: &tasks)
                case .multiply(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.multiply, on: &tasks)
                case .divide(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.divide, on: &tasks)
                case .modulo(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.modulo, on: &tasks)
                case .integerDivide(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.integerDivide, on: &tasks)
                case .equal(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.equal, on: &tasks)
                case .notEqual(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.notEqual, on: &tasks)
                case .lessThan(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.lessThan, on: &tasks)
                case .lessOrEqual(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.lessOrEqual, on: &tasks)
                case .greaterThan(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.greaterThan, on: &tasks)
                case .greaterOrEqual(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.greaterOrEqual, on: &tasks)
                case .and(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.and, on: &tasks)
                case .or(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.or, on: &tasks)
                case .in(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.in, on: &tasks)
                case .subset(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.subset, on: &tasks)
                case .union(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.union, on: &tasks)
                case .intersection(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.intersection, on: &tasks)
                case .setDifference(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.setDifference, on: &tasks)
                case .tupleDynamicAccess(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.tupleDynamicAccess, on: &tasks)
                case .tupleAppend(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.tupleAppend, on: &tasks)
                case .tupleConcatenate(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.tupleConcatenate, on: &tasks)
                case .functionApply(.variable(let name), let argument)
                    where scope.values[name] == nil && scope.operators.keys.contains(name):
                    let operation = try operatorID(named: name, arity: 1, scope: scope, at: path)
                    let isBounded = boundedLocalOperators.contains(operation)
                    schedule(
                        [(argument, "\(path).right")],
                        at: path,
                        scope: scope,
                        operatorReferences: [operation],
                        build: {
                            isBounded
                                ? .functionApply(.operatorReference(operation), $0[0])
                                : .recursiveCall(operation, [$0[0]])
                        },
                        on: &tasks
                    )
                case .functionApply(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.functionApply, on: &tasks)
                case .functionSet(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.functionSet, on: &tasks)
                case .setSum(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, scope: scope, build: CompiledStateExpr.setSum, on: &tasks)
                case .integerRange(let lower, let upper):
                    schedule([(lower, "\(path).lower"), (upper, "\(path).upper")], at: path, scope: scope, build: { .integerRange($0[0], $0[1]) }, on: &tasks)
                case .ifThenElse(let condition, let then, let otherwise):
                    schedule([(condition, "\(path).condition"), (then, "\(path).then"), (otherwise, "\(path).else")], at: path, scope: scope, build: { .ifThenElse($0[0], $0[1], $0[2]) }, on: &tasks)
                case .setLiteral(let values):
                    schedule(indexed(values, at: path), at: path, scope: scope, build: CompiledStateExpr.setLiteral, on: &tasks)
                case .tupleLiteral(let values):
                    schedule(indexed(values, at: path), at: path, scope: scope, build: CompiledStateExpr.tupleLiteral, on: &tasks)
                case .tupleAccess(let value, let index):
                    schedule([(value, path)], at: path, scope: scope, build: { .tupleAccess($0[0], index) }, on: &tasks)
                case .recordLiteral(let record):
                    var seen: Set<String> = []
                    let fields = try record.fields.enumerated().map { index, item in
                        let fieldPath = "\(path).fields[\(index)]"
                        guard seen.insert(item.name).inserted else {
                            throw CompilationDiagnostic(
                                code: .duplicateRecordField,
                                stage: .validation,
                                path: "\(fieldPath).declaration",
                                expected: "one declaration for each record field",
                                actual: "a repeated record field '\(item.name)'",
                                nextSafeAction: "Give each record field a distinct name."
                            )
                        }
                        return (
                            id: try field(named: item.name, at: "\(fieldPath).declaration"),
                            key: CompiledValue.string(item.name),
                            expression: item.value,
                            path: "\(fieldPath).value"
                        )
                    }
                    schedule(fields.map { ($0.expression, $0.path) }, at: path, scope: scope, build: { values in
                        .recordLiteral(.init(zip(fields, values).map { field, value in
                            .init(id: field.id, key: field.key, value: value)
                        }))
                    }, on: &tasks)
                case .recordAccess(let value, let name):
                    let id = try field(named: name, at: "\(path).field")
                    schedule([(value, "\(path).value")], at: path, scope: scope, build: { .recordAccess($0[0], id, .string(name)) }, on: &tasks)
                case .except(let function, let key, let value):
                    schedule([(function, "\(path).function"), (key, "\(path).key"), (value, "\(path).value")], at: path, scope: scope, build: { .except($0[0], $0[1], $0[2]) }, on: &tasks)
                case .caseExpr(let branches, let otherwise):
                    guard branches.isEmpty == false, branches.count.isMultiple(of: 2) else {
                        throw CompilationDiagnostic(
                            code: .invalidFormalDeclaration,
                            stage: .validation,
                            path: path,
                            expected: "at least one complete CASE condition and value pair",
                            actual: branches.isEmpty ? "no CASE branches" : "an unmatched CASE branch",
                            nextSafeAction: "Provide complete condition and value pairs before an optional OTHER expression."
                        )
                    }
                    var children = branches.enumerated().map { ($0.element, "\(path).branch[\($0.offset)]") }
                    if let otherwise { children.append((otherwise, "\(path).otherwise")) }
                    schedule(children, at: path, scope: scope, build: { values in
                        var compiledBranches: [CompiledCaseBranch] = []
                        for index in stride(from: 0, to: branches.count, by: 2) {
                            compiledBranches.append(.init(condition: values[index], value: values[index + 1]))
                        }
                        guard let first = compiledBranches.first else { throw Self.invalidTraversal(at: path) }
                        return .caseExpr(
                            first,
                            Array(compiledBranches.dropFirst()),
                            otherwise: values.count == branches.count ? nil : values.last
                        )
                    }, on: &tasks)
                case .setFilter(let domain, let name, let body):
                    let nested = try bind([name], at: "\(path).binder", scope: scope)
                    scheduleBinding(
                        domain,
                        body,
                        binder: try bound(name, in: nested, at: "\(path).binder"),
                        at: path,
                        scope: scope,
                        bodyScope: nested,
                        build: CompiledStateExpr.setFilter,
                        on: &tasks
                    )
                case .setMap(let body, let name, let domain):
                    let nested = try bind([name], at: "\(path).binder", scope: scope)
                    let binder = try bound(name, in: nested, at: "\(path).binder")
                    schedule(
                        [(body, "\(path).body"), (domain, "\(path).domain")],
                        at: path,
                        scope: scope,
                        childScopes: [nested, scope],
                        build: { .setMap($0[0], binder, $0[1]) },
                        on: &tasks
                    )
                case .functionLiteral(let domain, let name, let body):
                    let nested = try bind([name], at: "\(path).binder", scope: scope)
                    scheduleBinding(domain, body, binder: try bound(name, in: nested, at: path), at: path, scope: scope, bodyScope: nested, build: CompiledStateExpr.functionLiteral, on: &tasks)
                case .forAll(let domain, let name, let body):
                    let nested = try bind([name], at: "\(path).binder", scope: scope)
                    scheduleBinding(domain, body, binder: try bound(name, in: nested, at: path), at: path, scope: scope, bodyScope: nested, build: CompiledStateExpr.forAll, on: &tasks)
                case .exists(let domain, let name, let body):
                    let nested = try bind([name], at: "\(path).binder", scope: scope)
                    scheduleBinding(domain, body, binder: try bound(name, in: nested, at: path), at: path, scope: scope, bodyScope: nested, build: CompiledStateExpr.exists, on: &tasks)
                case .choose(let domain, let name, let body):
                    let nested = try bind([name], at: "\(path).binder", scope: scope)
                    scheduleBinding(domain, body, binder: try bound(name, in: nested, at: path), at: path, scope: scope, bodyScope: nested, build: CompiledStateExpr.choose, on: &tasks)
                case .foldFunction(let lambda, let initial, let sequence):
                    if let issue = lambda.sourceIssue {
                        throw issue.compilationDiagnostic(stage: .binding, path: "\(path).operator")
                    }
                    let nested = try bind(lambda.parameters, at: "\(path).parameters", scope: scope)
                    let parameters = try lambda.parameters.map { try bound($0, in: nested, at: path) }
                    schedule([(lambda.body, "\(path).body"), (initial, "\(path).initial"), (sequence, "\(path).sequence")], at: path, scope: scope, childScopes: [nested, scope, scope], build: {
                        .foldFunction(.init(parameters: parameters, body: $0[0]), initial: $0[1], sequence: $0[2])
                    }, on: &tasks)
                case .operatorApplication(let operation, let arguments):
                    guard operation.arity == arguments.count else {
                        throw invalidOperatorApplication(
                            at: path,
                            expected: "\(operation.arity) formal operator arguments",
                            actual: "\(arguments.count) arguments"
                        )
                    }
                    switch operation {
                    case .lambda(let lambda):
                        if let issue = lambda.sourceIssue {
                            throw issue.compilationDiagnostic(stage: .binding, path: "\(path).operator")
                        }
                        let nested = try bind(lambda.parameters, at: "\(path).operator.parameters", scope: scope)
                        let parameters = try lambda.parameters.map { try bound($0, in: nested, at: path) }
                        let valueArguments = try arguments.enumerated().map { index, argument in
                            guard case .value(let value) = argument else {
                                throw invalidOperatorApplication(
                                    at: "\(path).arguments[\(index)]",
                                    expected: "a formal value argument for a lambda",
                                    actual: "a formal operator argument"
                                )
                            }
                            return value
                        }
                        let children = [(lambda.body, "\(path).operator.body")]
                            + indexed(valueArguments, at: "\(path).arguments")
                        schedule(
                            children,
                            at: path,
                            scope: scope,
                            childScopes: [nested] + Array(repeating: scope, count: valueArguments.count),
                            build: { values in
                                guard let body = values.first else { throw Self.invalidTraversal(at: path) }
                                return .lambdaApplication(
                                    .init(parameters: parameters, body: body),
                                    Array(values.dropFirst())
                                )
                            },
                            on: &tasks
                        )
                    case .reference(let name, let arity):
                        let operation = try operatorID(named: name, arity: arity, scope: scope, at: "\(path).operator")
                        let argumentPlans = try arguments.enumerated().map {
                            try formalArgumentPlan(
                                $0.element,
                                scope: scope,
                                at: "\(path).arguments[\($0.offset)]"
                            )
                        }
                        let references = Set([operation]).union(
                            argumentPlans.flatMap(\.operatorReferences)
                        )
                        let formal = formalChildren(arguments: arguments, plans: argumentPlans, scope: scope, at: path)
                        schedule(formal.children, at: path, scope: scope, childScopes: formal.scopes, operatorReferences: references, build: { values in
                            var index = 0
                            let compiledArguments = try argumentPlans.map {
                                try Self.materialize($0.lowering, from: values, index: &index, at: path)
                            }
                            guard index == values.count else { throw Self.invalidTraversal(at: path) }
                            return .operatorApplication(operation, compiledArguments)
                        }, on: &tasks)
                    }
                case .recursiveCall(let name, let arguments):
                    let id = try operatorID(named: name, arity: arguments.count, scope: scope, at: path)
                    let isBounded = boundedLocalOperators.contains(id)
                    schedule(
                        indexed(arguments, at: "\(path).arguments"),
                        at: path,
                        scope: scope,
                        operatorReferences: [id],
                        build: {
                            if isBounded, let argument = $0.first {
                                return .functionApply(.operatorReference(id), argument)
                            }
                            return .recursiveCall(id, $0)
                        },
                        on: &tasks
                    )
                case .letValue(let name, let value, let body):
                    let nested = try bind([name], at: "\(path).binder", scope: scope)
                    let binder = try bound(name, in: nested, at: path)
                    schedule([(value, "\(path).value"), (body, "\(path).body")], at: path, scope: scope, childScopes: [scope, nested], build: { .letValue(binder, $0[0], $0[1]) }, on: &tasks)
                case .letIn(let operators, let body):
                    try requireDistinct(operators.map(\.name), at: "\(path).operators")
                    var nested = scope
                    var declarations: [(LocalOperator, OperatorID)] = []
                    for operation in operators {
                        if let issue = operation.sourceIssue {
                            throw issue.compilationDiagnostic(stage: .binding, path: "\(path).\(operation.name)")
                        }
                        try requireDeclarationName(operation.name, kind: "local operator", at: path)
                        let id = allocateOperator(operation.name, arity: operation.parameters.count)
                        if case .some = operation.domain {
                            boundedLocalOperators.insert(id)
                        }
                        nested.operators[operation.name] = id
                        declarations.append((operation, id))
                    }
                    var bindings: [(
                        id: OperatorID,
                        parameters: [BinderID],
                        hasDomain: Bool
                    )] = []
                    var children: [(expression: StateExpr, path: String)] = []
                    var childScopes: [BindingScope] = []
                    for (operation, id) in declarations {
                        let operationPath = "\(path).\(operation.name)"
                        let parameterScope = try bind(
                            operation.parameters,
                            at: "\(operationPath).parameters",
                            scope: nested
                        )
                        let parameters = try operation.parameters.map {
                            try bound($0, in: parameterScope, at: operationPath)
                        }
                        let hasDomain: Bool
                        if let domain = operation.domain {
                            children.append((domain, "\(operationPath).domain"))
                            childScopes.append(nested)
                            hasDomain = true
                        } else {
                            hasDomain = false
                        }
                        children.append((operation.body, "\(operationPath).body"))
                        childScopes.append(parameterScope)
                        bindings.append((id, parameters, hasDomain))
                    }
                    children.append((body, "\(path).body"))
                    childScopes.append(nested)
                    tasks.append(.build(childCount: children.count, path: path) { plans in
                        var index = 0
                        var declarations: [(
                            id: OperatorID,
                            parameters: [BinderID],
                            domain: CompiledStateExpr?,
                            body: CompiledStateExpr,
                            references: Set<OperatorID>
                        )] = []
                        for binding in bindings {
                            let domain: LoweredStateExpression?
                            if binding.hasDomain {
                                domain = plans[index]
                                index += 1
                            } else {
                                domain = nil
                            }
                            let body = plans[index]
                            index += 1
                            declarations.append((
                                binding.id,
                                binding.parameters,
                                domain?.expression,
                                body.expression,
                                body.operatorReferences.union(domain?.operatorReferences ?? [])
                            ))
                        }
                        guard index == plans.count - 1, let body = plans.last else {
                            throw Self.invalidTraversal(at: path)
                        }
                        let localIDs = Set(declarations.map(\.id))
                        let dependencies = Dictionary(uniqueKeysWithValues: declarations.map {
                            ($0.id, $0.references.intersection(localIDs))
                        })
                        let recursive = Set(localIDs.filter { start in
                            var pending = Array(dependencies[start, default: []])
                            var visited: Set<OperatorID> = []
                            while let current = pending.popLast() {
                                if current == start { return true }
                                guard visited.insert(current).inserted else { continue }
                                pending.append(contentsOf: dependencies[current, default: []])
                            }
                            return false
                        })
                        var references = body.operatorReferences.subtracting(localIDs)
                        for declaration in declarations {
                            references.formUnion(declaration.references.subtracting(localIDs))
                        }
                        return .init(
                            expression: .letIn(
                                declarations.map {
                                    .init(
                                        id: $0.id,
                                        parameters: $0.parameters,
                                        domain: $0.domain,
                                        body: $0.body,
                                        isRecursive: recursive.contains($0.id)
                                    )
                                },
                                body.expression
                            ),
                            operatorReferences: references
                        )
                    })
                    for (index, child) in children.enumerated().reversed() {
                        tasks.append(.expression(
                            child.expression,
                            path: child.path,
                            scope: childScopes[index]
                        ))
                    }
                }
            case .build(let childCount, let path, let build):
                guard lowered.count >= childCount else { throw Self.invalidTraversal(at: path) }
                let start = lowered.count - childCount
                let range = start..<lowered.endIndex
                let children = Array(lowered[range])
                lowered.removeSubrange(range)
                lowered.append(try build(children))
            }
        }
        guard lowered.count == 1, let result = lowered.first else {
            throw Self.invalidTraversal(at: path)
        }
        return (result.expression, result.operatorReferences)
    }

    private func schedule(
        _ children: [(expression: StateExpr, path: String)],
        at path: String,
        scope: BindingScope,
        childScopes: [BindingScope]? = nil,
        operatorReferences: Set<OperatorID> = [],
        build: @escaping ([CompiledStateExpr]) throws -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        tasks.append(.build(childCount: children.count, path: path) { children in
            var references = operatorReferences
            for child in children {
                references.formUnion(child.operatorReferences)
            }
            return .init(
                expression: try build(children.map(\.expression)),
                operatorReferences: references
            )
        })
        for (index, child) in children.enumerated().reversed() {
            tasks.append(.expression(
                child.expression,
                path: child.path,
                scope: childScopes?[index] ?? scope
            ))
        }
    }

    private func scheduleUnary(
        _ value: StateExpr,
        at path: String,
        scope: BindingScope,
        build: @escaping (CompiledStateExpr) -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        schedule([(value, path)], at: path, scope: scope, build: { build($0[0]) }, on: &tasks)
    }

    private func scheduleBinary(
        _ lhs: StateExpr,
        _ rhs: StateExpr,
        at path: String,
        scope: BindingScope,
        build: @escaping (CompiledStateExpr, CompiledStateExpr) -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        schedule(
            [(lhs, "\(path).left"), (rhs, "\(path).right")],
            at: path,
            scope: scope,
            build: { build($0[0], $0[1]) },
            on: &tasks
        )
    }

    private func scheduleBinding(
        _ domain: StateExpr,
        _ body: StateExpr,
        binder: BinderID,
        at path: String,
        scope: BindingScope,
        bodyScope: BindingScope,
        build: @escaping (CompiledStateExpr, BinderID, CompiledStateExpr) -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        schedule(
            [(domain, "\(path).domain"), (body, "\(path).body")],
            at: path,
            scope: scope,
            childScopes: [scope, bodyScope],
            build: { build($0[0], binder, $0[1]) },
            on: &tasks
        )
    }

    private func indexed(_ expressions: [StateExpr], at path: String) -> [(StateExpr, String)] {
        expressions.enumerated().map { ($0.element, "\(path)[\($0.offset)]") }
    }

    private mutating func formalOperatorPlan(
        _ operation: FormalOperator,
        scope: BindingScope,
        at path: String
    ) throws -> (lowering: FormalOperatorLoweringPlan, bodyScope: BindingScope?) {
        switch operation {
        case .reference(let name, let arity):
            return (
                .reference(try operatorID(named: name, arity: arity, scope: scope, at: path), arity: arity),
                nil
            )
        case .lambda(let lambda):
            if let issue = lambda.sourceIssue {
                throw issue.compilationDiagnostic(stage: .binding, path: path)
            }
            let nested = try bind(lambda.parameters, at: "\(path).parameters", scope: scope)
            return (
                .lambda(try lambda.parameters.map { try bound($0, in: nested, at: path) }),
                nested
            )
        }
    }

    private mutating func formalArgumentPlan(
        _ argument: FormalCallArgument,
        scope: BindingScope,
        at path: String
    ) throws -> FormalArgumentBindingPlan {
        switch argument {
        case .value:
            return .init(lowering: .value, bodyScope: nil, operatorReferences: [])
        case .operator(let operation):
            let plan = try formalOperatorPlan(operation, scope: scope, at: path)
            let references: Set<OperatorID>
            switch plan.lowering {
            case .reference(let id, _): references = [id]
            case .lambda: references = []
            }
            return .init(
                lowering: .operator(plan.lowering),
                bodyScope: plan.bodyScope,
                operatorReferences: references
            )
        }
    }

    private func formalChildren(
        arguments: [FormalCallArgument],
        plans: [FormalArgumentBindingPlan],
        scope: BindingScope,
        at path: String
    ) -> (children: [(StateExpr, String)], scopes: [BindingScope]) {
        var children: [(StateExpr, String)] = []
        var scopes: [BindingScope] = []
        for (index, argument) in arguments.enumerated() {
            let argumentPath = "\(path).arguments[\(index)]"
            switch argument {
            case .value(let value):
                children.append((value, argumentPath))
                scopes.append(scope)
            case .operator(.lambda(let lambda)):
                children.append((lambda.body, "\(argumentPath).body"))
                scopes.append(plans[index].bodyScope ?? scope)
            case .operator(.reference): break
            }
        }
        return (children, scopes)
    }

    private static func materialize(
        _ plan: FormalOperatorLoweringPlan,
        from children: [CompiledStateExpr],
        index: inout Int,
        at path: String
    ) throws -> CompiledFormalOperator {
        switch plan {
        case .reference(let id, let arity): return .reference(id, arity: arity)
        case .lambda(let parameters):
            return .lambda(.init(parameters: parameters, body: try child(from: children, index: &index, at: path)))
        }
    }

    private static func materialize(
        _ plan: FormalArgumentLoweringPlan,
        from children: [CompiledStateExpr],
        index: inout Int,
        at path: String
    ) throws -> CompiledFormalCallArgument {
        switch plan {
        case .value: return .value(try child(from: children, index: &index, at: path))
        case .operator(let operation): return .operator(try materialize(operation, from: children, index: &index, at: path))
        }
    }

    private static func child(
        from children: [CompiledStateExpr],
        index: inout Int,
        at path: String
    ) throws -> CompiledStateExpr {
        guard children.indices.contains(index) else { throw invalidTraversal(at: path) }
        let expression = children[index]
        index += 1
        return expression
    }

    private static func invalidTraversal(at path: String) -> CompilationDiagnostic {
        .init(
            code: .invalidFormalDeclaration,
            stage: .lowering,
            path: path,
            expected: "one compiled expression for each source expression",
            actual: "the lowering traversal produced an inconsistent expression stack",
            nextSafeAction: "Retain the source model and report this compiler defect."
        )
    }

    private mutating func lower(
        _ expression: TemporalExpr,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledTemporalExpr {
        switch expression {
        case .always(let predicate):
            return .always(try lower(predicate, at: "\(path).body", scope: scope))
        case .eventually(let predicate):
            return .eventually(try lower(predicate, at: "\(path).body", scope: scope))
        case .alwaysEventually(let predicate):
            return .alwaysEventually(try lower(predicate, at: "\(path).body", scope: scope))
        case .eventuallyAlways(let predicate):
            return .eventuallyAlways(try lower(predicate, at: "\(path).body", scope: scope))
        case .leadsTo(let from, let to):
            return .leadsTo(
                try lower(from, at: "\(path).from", scope: scope),
                try lower(to, at: "\(path).to", scope: scope)
            )
        }
    }

    private mutating func lower(
        _ action: ActionExpr,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledActionExpr {
        var tasks = [ActionLoweringTask.expression(action, path: path, scope: scope)]
        var lowered: [CompiledActionExpr] = []
        while let task = tasks.popLast() {
            switch task {
            case .build(let childCount, let taskPath, let build):
                guard lowered.count >= childCount else { throw Self.invalidTraversal(at: taskPath) }
                let start = lowered.count - childCount
                let children = Array(lowered[start...])
                lowered.removeSubrange(start...)
                lowered.append(try build(children))
            case .expression(let expression, let taskPath, let scope):
                switch expression {
                case .assign(let target, let value):
                    lowered.append(try .assign(
                        assignmentTarget(target, scope: scope, at: "\(taskPath).assign"),
                        lower(value, at: "\(taskPath).value", scope: scope)
                    ))
                case .unchanged(let target):
                    lowered.append(try .unchanged(assignmentTarget(target, scope: scope, at: "\(taskPath).unchanged")))
                case .guard_(let condition):
                    lowered.append(try .guard_(lower(condition, at: "\(taskPath).guard", scope: scope)))
                case .chooseAction(let target, let set):
                    lowered.append(try .chooseAction(
                        assignmentTarget(target, scope: scope, at: "\(taskPath).choose"),
                        lower(set, at: "\(taskPath).set", scope: scope)
                    ))
                case .existsAction(let name, let set, let body):
                    let nested = try bind([name], at: "\(taskPath).binder", scope: scope)
                    let binder = try bound(name, in: nested, at: taskPath)
                    let compiledSet = try lower(set, at: "\(taskPath).set", scope: scope)
                    scheduleAction(
                        [(body, "\(taskPath).body")],
                        at: taskPath,
                        scope: nested,
                        build: { .existsAction(binder, compiledSet, $0[0]) },
                        on: &tasks
                    )
                case .define(let name, let value, let body):
                    let nested = try bind([name], at: "\(taskPath).binder", scope: scope)
                    let binder = try bound(name, in: nested, at: taskPath)
                    let compiledValue = try lower(value, at: "\(taskPath).value", scope: scope)
                    scheduleAction(
                        [(body, "\(taskPath).body")],
                        at: taskPath,
                        scope: nested,
                        build: { .define(binder, compiledValue, $0[0]) },
                        on: &tasks
                    )
                case .ifElse(let condition, let then, let otherwise):
                    let compiledCondition = try lower(condition, at: "\(taskPath).condition", scope: scope)
                    scheduleAction(
                        [(then, "\(taskPath).then"), (otherwise, "\(taskPath).else")],
                        at: taskPath,
                        scope: scope,
                        build: { .ifElse(compiledCondition, $0[0], $0[1]) },
                        on: &tasks
                    )
                case .and(let lhs, let rhs):
                    scheduleAction(
                        [(lhs, "\(taskPath).left"), (rhs, "\(taskPath).right")],
                        at: taskPath,
                        scope: scope,
                        build: { .and($0[0], $0[1]) },
                        on: &tasks
                    )
                case .or(let lhs, let rhs):
                    scheduleAction(
                        [(lhs, "\(taskPath).left"), (rhs, "\(taskPath).right")],
                        at: taskPath,
                        scope: scope,
                        build: { .or($0[0], $0[1]) },
                        on: &tasks
                    )
                }
            }
        }
        guard lowered.count == 1, let expression = lowered.first else {
            throw Self.invalidTraversal(at: path)
        }
        return expression
    }

    private func scheduleAction(
        _ children: [(expression: ActionExpr, path: String)],
        at path: String,
        scope: BindingScope,
        build: @escaping ([CompiledActionExpr]) throws -> CompiledActionExpr,
        on tasks: inout [ActionLoweringTask]
    ) {
        tasks.append(.build(childCount: children.count, path: path, build))
        for child in children.reversed() {
            tasks.append(.expression(child.expression, path: child.path, scope: scope))
        }
    }

    private mutating func lower(
        _ initialization: VariableInitialization,
        at path: String,
        scope: BindingScope
    ) throws -> CompiledVariableInitialization {
        switch initialization {
        case .value(let value): return .value(.init(formal: value))
        case .expression(let expression): return .expression(try lower(expression, at: path, scope: scope))
        case .memberOf(let set): return .memberOf(try lower(set, at: path, scope: scope))
        }
    }

    private func value(
        named name: String,
        scope: BindingScope,
        at path: String
    ) throws -> CompiledStateExpr {
        if let binder = scope.values[name] { return .boundValue(binder) }
        if let variable = layout.variables.first(where: { $0.declaration.name == name })?.id {
            return .stateVariable(variable)
        }
        if let value = constants.first(where: { $0.name == name })?.value {
            return .value(value)
        }
        if formalParameters.contains(name) { return .value(.constant(name)) }
        if incomingModuleParameters.contains(where: { $0.operatorName == name }) {
            return .value(.constant(name))
        }
        if let operation = scope.operators[name] {
            guard operatorArities[operation] == 0 else {
                throw invalidOperatorApplication(
                    at: path,
                    expected: "a zero-arity operator in value position",
                    actual: "operator '\(name)' requires \(operatorArities[operation] ?? 0) arguments"
                )
            }
            return .operatorReference(operation)
        }
        throw CompilationDiagnostic(
            code: knownBinderNames.contains(name) ? .outOfScopeReference : .unknownReference,
            stage: .binding,
            path: path,
            expected: "a declared variable, scoped binder, or linked symbol",
            actual: "unresolved name '\(name)'",
            nextSafeAction: "Use a declaration available in this lexical scope."
        )
    }

    private func variable(named name: String, at path: String) throws -> VariableID {
        guard let variable = layout.variables.first(where: { $0.declaration.name == name })?.id else {
            throw diagnostic(path: path, actual: "unresolved variable '\(name)'")
        }
        return variable
    }

    private func assignmentTarget(
        _ target: ActionTarget,
        scope: BindingScope,
        at path: String
    ) throws -> VariableID {
        switch target {
        case .programCounter:
            guard let variable = layout.programCounterID() else { throw diagnostic(path: path) }
            return variable
        case .procedureStack:
            guard let variable = layout.procedureStackID() else { throw diagnostic(path: path) }
            return variable
        case .named(let name):
            guard scope.values[name] == nil else {
                throw CompilationDiagnostic(
                    code: .assignmentToBinder,
                    stage: .binding,
                    path: path,
                    expected: "an assignable declared state variable",
                    actual: "binder '\(name)'",
                    nextSafeAction: "Assign a declared state variable."
                )
            }
            if let variable = layout.variables.first(where: { $0.declaration.name == name })?.id {
                return variable
            }
            if knownBinderNames.contains(name) {
                throw CompilationDiagnostic(
                    code: .assignmentToBinder,
                    stage: .binding,
                    path: path,
                    expected: "an assignable declared state variable",
                    actual: "binder '\(name)'",
                    nextSafeAction: "Assign a declared state variable."
                )
            }
            throw diagnostic(path: path, actual: "unresolved variable '\(name)'")
        }
    }

    private func action(named name: String, at path: String) throws -> ActionID {
        guard let action = layout.actions.first(where: { $0.declaration.name == name })?.id else {
            throw diagnostic(path: path, actual: "unresolved action '\(name)'")
        }
        return action
    }

    private func controlLocation(
        _ reference: ControlLocationReference,
        owner: ControlOwner,
        at path: String
    ) throws -> ControlLocationID {
        let resolvedOwner: ControlOwner
        if reference.sourceName == CompilerControlSymbol.done.rawValue {
            let algorithm: String
            switch owner {
            case .sequential(let name), .process(let name, _, _), .procedure(let name, _), .generated(let name, _):
                algorithm = name
            }
            resolvedOwner = .generated(
                algorithm: algorithm,
                purpose: CompilerControlSymbol.done.rawValue
            )
        } else {
            resolvedOwner = owner
        }
        let location = layout.controlLocations.first {
            $0.owner == resolvedOwner && $0.sourceName == reference.sourceName
        }?.id
        guard let location else {
            throw diagnostic(path: path, actual: "unresolved control location '\(reference.sourceName)'")
        }
        return location
    }

    private func field(named name: String, at path: String) throws -> FieldID {
        guard isFormalIdentifier(name) else {
            throw CompilationDiagnostic(
                code: .invalidFormalDeclaration,
                stage: .binding,
                path: path,
                expected: "a formal record-field identifier",
                actual: "invalid record field '\(name)'",
                nextSafeAction: "Use an ASCII identifier beginning with a letter or underscore."
            )
        }
        guard let field = layout.fields.first(where: { $0.renderedName == name })?.id else {
            throw diagnostic(path: path, actual: "unresolved field '\(name)'")
        }
        return field
    }

    private func operatorID(
        named name: String,
        arity: Int,
        scope: BindingScope,
        at path: String
    ) throws -> OperatorID {
        guard let operation = scope.operators[name] else {
            throw CompilationDiagnostic(
                code: .unresolvedImportedSymbol,
                stage: .binding,
                path: path,
                expected: "a linked formal operator",
                actual: "unresolved symbol '\(name)'",
                nextSafeAction: "Declare or import the operator before this use."
            )
        }
        guard operatorArities[operation] == arity else {
            throw invalidOperatorApplication(
                at: path,
                expected: "\(operatorArities[operation] ?? 0) formal operator arguments",
                actual: "\(arity) arguments"
            )
        }
        return operation
    }

    private mutating func bind(
        _ names: [String],
        at path: String,
        scope: BindingScope
    ) throws -> BindingScope {
        try requireDistinct(names, at: path)
        var nested = scope
        for name in names {
            let binder = try allocateBinder(name, in: nested, at: path)
            nested.values[name] = binder
        }
        return nested
    }

    private mutating func bind(
        _ parameters: [FormalParameter],
        at path: String,
        scope: BindingScope
    ) throws -> BindingScope {
        try requireDistinct(parameters.map(\.name), at: path)
        var nested = scope
        for parameter in parameters {
            guard isFormalIdentifier(parameter.name) else {
                throw CompilationDiagnostic(
                    code: .invalidFormalDeclaration,
                    stage: .binding,
                    path: path,
                    expected: "a formal parameter identifier",
                    actual: "invalid formal parameter '\(parameter.name)'",
                    nextSafeAction: "Use an ASCII identifier beginning with a letter or underscore."
                )
            }
            switch parameter {
            case .value(let name):
                nested.values[name] = try allocateBinder(name, in: nested, at: path)
            case .operator(let name, let arity):
                let operation = allocateOperator(name, arity: arity)
                nested.operators[name] = operation
            }
        }
        return nested
    }

    private func compiledParameters(
        _ parameters: [FormalParameter],
        scope: BindingScope,
        at path: String
    ) throws -> [CompiledFormalParameter] {
        try parameters.map { parameter in
            switch parameter {
            case .value(let name): return .value(try bound(name, in: scope, at: path))
            case .operator(let name, let arity):
                return .operator(try operatorID(named: name, arity: arity, scope: scope, at: path), arity: arity)
            }
        }
    }

    private mutating func allocateBinder(
        _ name: String,
        renderedName explicitRenderedName: String? = nil,
        in scope: BindingScope,
        at path: String
    ) throws -> BinderID {
        guard isFormalIdentifier(name) else {
            throw CompilationDiagnostic(
                code: .invalidFormalDeclaration,
                stage: .binding,
                path: path,
                expected: "a formal binder identifier",
                actual: "invalid binder '\(name)'",
                nextSafeAction: "Use an ASCII identifier beginning with a letter or underscore."
            )
        }
        let binder = BinderID(ordinal: nextBinderOrdinal)
        nextBinderOrdinal += 1
        knownBinderNames.insert(name)
        var preferredRenderedName = explicitRenderedName ?? name
        while isPlusCalDeclarationName(preferredRenderedName) == false {
            preferredRenderedName = "_\(preferredRenderedName)"
        }
        var unavailableNames = reservedRenderedNames
        unavailableNames.formUnion(scope.values.values.compactMap { binderNames[$0] })
        unavailableNames.formUnion(scope.operators.values.compactMap { operatorNames[$0] })
        let renderedName = StateExpr.freshBoundName(preferredRenderedName, avoiding: unavailableNames)
        binderNames[binder] = renderedName
        return binder
    }

    private mutating func allocateOperator(_ name: String, arity: Int) -> OperatorID {
        let operation = OperatorID(ordinal: nextOperatorOrdinal)
        nextOperatorOrdinal += 1
        operatorNames[operation] = name
        operatorArities[operation] = arity
        return operation
    }

    private func bound(_ name: String, in scope: BindingScope, at path: String) throws -> BinderID {
        guard let binder = scope.values[name] else {
            throw diagnostic(path: path, actual: "unresolved binder '\(name)'")
        }
        return binder
    }

    private func validateValue(_ value: TLAValue, at path: String) throws {
        guard let member = symmetricMembers.first(where: { valueContains(value, $0) }) else { return }
        throw CompilationDiagnostic(
            code: .invalidSymmetricCollection,
            stage: .binding,
            path: path,
            expected: "logic invariant under exchangeable member renaming",
            actual: "authored expression names compiler-owned symmetric member '\(member)'",
            nextSafeAction: "Use the symmetric collection declaration instead of a concrete member."
        )
    }

    private func requireDistinct(_ names: [String], at path: String) throws {
        guard Set(names).count == names.count else {
            throw CompilationDiagnostic(
                code: .duplicateBinder,
                stage: .binding,
                path: path,
                expected: "one declaration for each name",
                actual: "duplicate declarations in \(names)",
                nextSafeAction: "Give each declaration a distinct name."
            )
        }
    }

    private func requireDeclarationName(_ name: String, kind: String, at path: String) throws {
        guard isTLADeclarationName(name) else {
            throw CompilationDiagnostic(
                code: .invalidFormalDeclaration,
                stage: .binding,
                path: path,
                expected: "a formal declaration identifier",
                actual: "invalid \(kind) name '\(name)'",
                nextSafeAction: "Use an ASCII identifier that is not reserved by TLA+."
            )
        }
    }

    private func invalidOperatorApplication(
        at path: String,
        expected: String,
        actual: String
    ) -> CompilationDiagnostic {
        .init(
            code: .invalidFormalOperatorApplication,
            stage: .binding,
            path: path,
            expected: expected,
            actual: actual,
            nextSafeAction: "Use the operator with its declared parameter shape."
        )
    }

    private func diagnostic(path: String, actual: String = "an unresolved compiler identity") -> CompilationDiagnostic {
        .init(
            code: .unknownReference,
            stage: .binding,
            path: path,
            expected: "a resolved compiler identity",
            actual: actual,
            nextSafeAction: "Declare or import the referenced value before this use."
        )
    }
}
