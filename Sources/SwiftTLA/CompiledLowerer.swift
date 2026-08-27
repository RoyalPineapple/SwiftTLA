private enum StateLoweringTask {
    case expression(StateExpr, path: String)
    case build(
        childCount: Int,
        path: String,
        ([CompiledStateExpr]) throws -> CompiledStateExpr
    )
}

private enum ActionLoweringTask {
    case expression(ActionExpr, path: String)
    case build(
        childCount: Int,
        path: String,
        ([CompiledActionExpr]) throws -> CompiledActionExpr
    )
}

private enum FormalOperatorLoweringPlan {
    case reference(OperatorID, arity: Int)
    case lambda([BinderID])
}

private enum FormalArgumentLoweringPlan {
    case value
    case `operator`(FormalOperatorLoweringPlan)
}

private struct LocalOperatorLoweringPlan {
    let id: OperatorID
    let parameters: [BinderID]
    let hasDomain: Bool
    let isRecursive: Bool
}

struct CompiledLowerer {
    let bindings: CompiledBindingTable
    let closure: FormalModuleClosure
    let layout: CompiledLayout

    func lower(spec: TLASpec) throws -> CompiledSemantics {
        var initializations: [VariableID: CompiledVariableInitialization] = [:]
        for declaration in spec.variables {
            let path = "variables.\(declaration.name)"
            let id = try variable(at: "\(path).declaration")
            initializations[id] = try lower(declaration.initialization, at: "\(path).initialization")
        }
        let actions: [CompiledAction] = try spec.actions.map {
            try lower($0)
        }
        let actionsByID = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        let invariants: [CompiledInvariant] = try spec.invariants.map {
            CompiledInvariant(
                id: try property(at: "invariants.\($0.name).declaration"),
                name: $0.name,
                body: try lower($0.body, at: "invariants.\($0.name).body")
            )
        }
        let temporalProperties = try spec.temporalProperties.map {
            CompiledTemporal(
                id: try property(at: "temporalProperties.\($0.name).declaration"),
                name: $0.name,
                expression: try lower($0.expr, at: "temporalProperties.\($0.name)")
            )
        }
        let theorems = try spec.theorems.map { theorem in
            if let temporal = theorem.temporalBody {
                return CompiledTheorem(
                    name: theorem.name,
                    body: .temporal(try lower(temporal, at: "theorems.\(theorem.name)"))
                )
            }
            if let state = theorem.stateBody {
                return CompiledTheorem(
                    name: theorem.name,
                    body: .state(try lower(state, at: "theorems.\(theorem.name)"))
                )
            }
            throw CompilationDiagnostic(
                code: .invalidFormalDeclaration,
                stage: .lowering,
                path: "theorems.\(theorem.name)",
                expected: "a temporal or state theorem body",
                actual: "no theorem body",
                nextSafeAction: "Declare a theorem with a supported temporal or state expression."
            )
        }
        let fairness = try spec.fairness.enumerated().map { offset, condition in
            try lower(condition, actions: actionsByID, at: "fairness[\(offset)]")
        }
        let formalOperators: [CompiledFormalOperatorDefinition] = try spec.formalOperatorDefinitions.map { definition in
            CompiledFormalOperatorDefinition(
                id: try operatorID(at: "formalOperators.\(definition.name).declaration"),
                parameters: try lower(definition.parameters, at: "formalOperators.\(definition.name).parameters"),
                body: try lower(definition.body, at: "formalOperators.\(definition.name).body")
            )
        }
        let recursiveFunctions: [CompiledRecursiveFunction] = try spec.recursiveFuncs.map { function in
            CompiledRecursiveFunction(
                id: try operatorID(at: "recursiveFunctions.\(function.name).declaration"),
                parameters: try function.params.map {
                    try binder(at: "recursiveFunctions.\(function.name).parameters.\($0)")
                },
                body: try lower(function.body, at: "recursiveFunctions.\(function.name).body")
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
                        at: "importConfigurations.\(configuration.moduleName).\(replacement.operatorName)"
                    )
                )
            }
        }
        let localFormalNames = Set(spec.formalOperatorDefinitions.map(\.name))
        let linkedFormalOperators = try closure.linkedOperators.formalOperatorDefinitions
            .filter { !localFormalNames.contains($0.name) }
            .map { definition in
                CompiledFormalOperatorDefinition(
                    id: try operatorID(at: "linkedFormalOperators.\(definition.name).declaration"),
                    parameters: try lower(definition.parameters, at: "linkedFormalOperators.\(definition.name).parameters"),
                    body: try lower(definition.body, at: "linkedFormalOperators.\(definition.name).body")
                )
            }
        let localRecursiveNames = Set(spec.recursiveFuncs.map(\.name))
        let linkedRecursiveFunctions = try closure.linkedOperators.recursiveFunctions
            .filter { !localRecursiveNames.contains($0.name) }
            .map { function in
                CompiledRecursiveFunction(
                    id: try operatorID(at: "linkedRecursiveFunctions.\(function.name).declaration"),
                    parameters: try function.params.map {
                        try binder(at: "linkedRecursiveFunctions.\(function.name).parameters.\($0)")
                    },
                    body: try lower(function.body, at: "linkedRecursiveFunctions.\(function.name).body")
                )
            }
        let allFormalOperators = formalOperators + linkedFormalOperators
        let allRecursiveFunctions = recursiveFunctions + linkedRecursiveFunctions
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
            theorems: theorems,
            fairness: fairness,
            constraint: try lowerOptional(spec.constraint, at: "constraint"),
            assume: try lowerOptional(spec.assume, at: "assume"),
            formalOperatorDefinitions: allFormalOperators,
            recursiveFunctions: allRecursiveFunctions,
            formalModuleReplacements: formalModuleReplacements,
            symmetrySets: spec.symmetrySets.map { symmetry in
                .init(values: symmetry.values)
            },
            symmetricCollections: try spec.symmetricCollections.map { collection in
                .init(
                    variable: try variable(at: "variables.\(collection.name).declaration"),
                    members: collection.metadata.members,
                    domainSymbol: collection.metadata.domainSymbol,
                    initial: .init(formal: collection.metadata.initial)
                )
            }
        )
    }

    func refinementExpression(_ expression: StateExpr, at path: String) throws -> CompiledStateExpr {
        try lower(expression, at: path)
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
                    code: .invalidVariableInitialization,
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
        case .weakFairness:
            action = try self.action(at: "\(path).action")
            arguments = nil
        case .strongFairness:
            action = try self.action(at: "\(path).action")
            arguments = nil
        case .weakFairnessActionCall(let value), .strongFairnessActionCall(let value):
            action = try self.action(at: "\(path).action")
            arguments = value.arguments
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

    private func lower(_ action: NamedAction) throws -> CompiledAction {
        if let issue = action.sourceIssue {
            throw issue.compilationDiagnostic(stage: .lowering, path: "actions.\(action.name).bindings")
        }
        let id = try self.action(at: "actions.\(action.name).declaration")
        let bindings = try action.bindings.map {
            CompiledActionBinding(
                binder: try binder(at: "actions.\(action.name).bindings.\($0.name)"),
                sourceName: $0.name,
                values: $0.values,
                generatedSwiftType: $0.generatedSwiftType
            )
        }
        let body = try lower(action.body, at: "actions.\(action.name).body")
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

    private func lowerOptional(_ expression: StateExpr?, at path: String) throws -> CompiledStateExpr? {
        guard let expression else { return nil }
        let source: StateExpr = expression
        return try lower(source, at: path)
    }

    private func lower(_ expression: StateExpr, at path: String) throws -> CompiledStateExpr {
        var tasks = [StateLoweringTask.expression(expression, path: path)]
        var lowered: [CompiledStateExpr] = []
        while let task = tasks.popLast() {
            switch task {
            case .expression(let expression, let path):
                switch expression {
                case .sourceIssue(let issue): throw issue.compilationDiagnostic(stage: .lowering, path: path)
                case .value(let value): lowered.append(.value(value))
                case .currentProcess, .processLocalFamily: throw diagnostic(path: path)
                case .programCounter, .procedureStack, .variable: lowered.append(try valueReference(at: path))
                case .controlLocation: lowered.append(.controlLocation(try controlLocation(at: path)))
                case .enabledAction: lowered.append(.enabledAction(try action(at: path)))
                case .negate(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.negate, on: &tasks)
                case .not(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.not, on: &tasks)
                case .cardinality(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.cardinality, on: &tasks)
                case .powerSet(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.powerSet, on: &tasks)
                case .unionAll(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.unionAll, on: &tasks)
                case .tupleLength(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.tupleLength, on: &tasks)
                case .tupleHead(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.tupleHead, on: &tasks)
                case .tupleTail(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.tupleTail, on: &tasks)
                case .domain(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.domain, on: &tasks)
                case .sequenceFromSet(let value): scheduleUnary(value, at: path, build: CompiledStateExpr.sequenceFromSet, on: &tasks)
                case .add(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.add, on: &tasks)
                case .subtract(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.subtract, on: &tasks)
                case .multiply(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.multiply, on: &tasks)
                case .divide(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.divide, on: &tasks)
                case .modulo(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.modulo, on: &tasks)
                case .integerDivide(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.integerDivide, on: &tasks)
                case .equal(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.equal, on: &tasks)
                case .notEqual(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.notEqual, on: &tasks)
                case .lessThan(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.lessThan, on: &tasks)
                case .lessOrEqual(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.lessOrEqual, on: &tasks)
                case .greaterThan(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.greaterThan, on: &tasks)
                case .greaterOrEqual(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.greaterOrEqual, on: &tasks)
                case .and(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.and, on: &tasks)
                case .or(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.or, on: &tasks)
                case .in(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.in, on: &tasks)
                case .subset(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.subset, on: &tasks)
                case .union(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.union, on: &tasks)
                case .intersection(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.intersection, on: &tasks)
                case .setDifference(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.setDifference, on: &tasks)
                case .tupleDynamicAccess(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.tupleDynamicAccess, on: &tasks)
                case .tupleAppend(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.tupleAppend, on: &tasks)
                case .tupleConcatenate(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.tupleConcatenate, on: &tasks)
                case .functionApply(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.functionApply, on: &tasks)
                case .functionSet(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.functionSet, on: &tasks)
                case .setSum(let lhs, let rhs): scheduleBinary(lhs, rhs, at: path, build: CompiledStateExpr.setSum, on: &tasks)
                case .integerRange(let lower, let upper):
                    schedule([(lower, "\(path).lower"), (upper, "\(path).upper")], at: path, build: { .integerRange($0[0], $0[1]) }, on: &tasks)
                case .ifThenElse(let condition, let then, let otherwise):
                    schedule([(condition, "\(path).condition"), (then, "\(path).then"), (otherwise, "\(path).else")], at: path, build: { .ifThenElse($0[0], $0[1], $0[2]) }, on: &tasks)
                case .setLiteral(let values):
                    schedule(indexed(values, at: path), at: path, build: CompiledStateExpr.setLiteral, on: &tasks)
                case .tupleLiteral(let values):
                    schedule(indexed(values, at: path), at: path, build: CompiledStateExpr.tupleLiteral, on: &tasks)
                case .tupleAccess(let value, let index):
                    schedule([(value, path)], at: path, build: { .tupleAccess($0[0], index) }, on: &tasks)
                case .recordLiteral(let record):
                    let fields = try record.fields.enumerated().map { index, item in
                        let fieldPath = "\(path).fields[\(index)]"
                        return (id: try field(at: "\(fieldPath).declaration"), key: CompiledValue.string(item.name), expression: item.value, path: "\(fieldPath).value")
                    }
                    schedule(fields.map { ($0.expression, $0.path) }, at: path, build: { values in
                        .recordLiteral(.init(zip(fields, values).map { field, value in
                            .init(id: field.id, key: field.key, value: value)
                        }))
                    }, on: &tasks)
                case .recordAccess(let value, let name):
                    let id = try field(at: "\(path).field")
                    schedule([(value, "\(path).value")], at: path, build: { .recordAccess($0[0], id, .string(name)) }, on: &tasks)
                case .except(let function, let key, let value):
                    schedule([(function, "\(path).function"), (key, "\(path).key"), (value, "\(path).value")], at: path, build: { .except($0[0], $0[1], $0[2]) }, on: &tasks)
                case .caseExpr(let branches, let otherwise):
                    var children = branches.enumerated().map { ($0.element, "\(path).branch[\($0.offset)]") }
                    if let otherwise { children.append((otherwise, "\(path).otherwise")) }
                    schedule(children, at: path, build: { values in
                        var compiledBranches: [CompiledCaseBranch] = []
                        for index in stride(from: 0, to: branches.count, by: 2) {
                            compiledBranches.append(.init(condition: values[index], value: values[index + 1]))
                        }
                        guard let first = compiledBranches.first else { throw invalidTraversal(at: path) }
                        return .caseExpr(
                            first,
                            Array(compiledBranches.dropFirst()),
                            otherwise: values.count == branches.count ? nil : values.last
                        )
                    }, on: &tasks)
                case .setFilter(let domain, let name, let body):
                    scheduleBinding(domain, body, binder: try binder(at: "\(path).binder.\(name)"), at: path, build: CompiledStateExpr.setFilter, on: &tasks)
                case .setMap(let body, let name, let domain):
                    let binder = try binder(at: "\(path).binder.\(name)")
                    schedule([(body, "\(path).body"), (domain, "\(path).domain")], at: path, build: { .setMap($0[0], binder, $0[1]) }, on: &tasks)
                case .functionLiteral(let domain, let name, let body):
                    scheduleBinding(domain, body, binder: try binder(at: "\(path).binder.\(name)"), at: path, build: CompiledStateExpr.functionLiteral, on: &tasks)
                case .forAll(let domain, let name, let body):
                    scheduleBinding(domain, body, binder: try binder(at: "\(path).binder.\(name)"), at: path, build: CompiledStateExpr.forAll, on: &tasks)
                case .exists(let domain, let name, let body):
                    scheduleBinding(domain, body, binder: try binder(at: "\(path).binder.\(name)"), at: path, build: CompiledStateExpr.exists, on: &tasks)
                case .choose(let domain, let name, let body):
                    scheduleBinding(domain, body, binder: try binder(at: "\(path).binder.\(name)"), at: path, build: CompiledStateExpr.choose, on: &tasks)
                case .foldFunction(let lambda, let initial, let sequence):
                    let parameters = try lambda.parameters.map { try binder(at: "\(path).parameters.\($0)") }
                    schedule([(lambda.body, "\(path).body"), (initial, "\(path).initial"), (sequence, "\(path).sequence")], at: path, build: {
                        .foldFunction(.init(parameters: parameters, body: $0[0]), initial: $0[1], sequence: $0[2])
                    }, on: &tasks)
                case .operatorApplication(let operation, let arguments):
                    switch operation {
                    case .lambda(let lambda):
                        let parameters = try lambda.parameters.map {
                            try binder(at: "\(path).operator.parameters.\($0)")
                        }
                        let valueArguments = try arguments.enumerated().map { index, argument in
                            guard case .value(let value) = argument else { throw invalidTraversal(at: "\(path).arguments[\(index)]") }
                            return value
                        }
                        schedule(
                            [(lambda.body, "\(path).operator.body")] + indexed(valueArguments, at: "\(path).arguments"),
                            at: path,
                            build: { values in
                                guard let body = values.first else { throw invalidTraversal(at: path) }
                                return .lambdaApplication(
                                    .init(parameters: parameters, body: body),
                                    Array(values.dropFirst())
                                )
                            },
                            on: &tasks
                        )
                    case .reference:
                        let operation = try operatorID(at: "\(path).operator")
                        let argumentPlans = try arguments.enumerated().map {
                            try formalArgumentPlan($0.element, at: "\(path).arguments[\($0.offset)]")
                        }
                        schedule(formalChildren(arguments: arguments, at: path), at: path, build: { values in
                            var index = 0
                            let compiledArguments = try argumentPlans.map {
                                try materialize($0, from: values, index: &index, at: path)
                            }
                            guard index == values.count else { throw invalidTraversal(at: path) }
                            return .operatorApplication(operation, compiledArguments)
                        }, on: &tasks)
                    }
                case .recursiveCall(_, let arguments):
                    let id = try operatorID(at: path)
                    schedule(indexed(arguments, at: "\(path).arguments"), at: path, build: { .recursiveCall(id, $0) }, on: &tasks)
                case .letValue(let name, let value, let body):
                    let binder = try binder(at: "\(path).binder.\(name)")
                    schedule([(value, "\(path).value"), (body, "\(path).body")], at: path, build: { .letValue(binder, $0[0], $0[1]) }, on: &tasks)
                case .letIn(let operators, let body):
                    let plans = try localOperatorPlans(operators, at: path)
                    var children: [(StateExpr, String)] = []
                    for operation in operators {
                        if let domain = operation.domain { children.append((domain, "\(path).\(operation.name).domain")) }
                        children.append((operation.body, "\(path).\(operation.name).body"))
                    }
                    children.append((body, "\(path).body"))
                    schedule(children, at: path, build: { values in
                        var index = 0
                        let compiled = try plans.map { plan in
                            let domain = plan.hasDomain ? try child(from: values, index: &index, at: path) : nil
                            return CompiledLocalOperator(id: plan.id, parameters: plan.parameters, domain: domain, body: try child(from: values, index: &index, at: path), isRecursive: plan.isRecursive)
                        }
                        let body = try child(from: values, index: &index, at: path)
                        guard index == values.count else { throw invalidTraversal(at: path) }
                        return .letIn(compiled, body)
                    }, on: &tasks)
                }
            case .build(let childCount, let path, let build):
                guard lowered.count >= childCount else { throw invalidTraversal(at: path) }
                let start = lowered.count - childCount
                let range = start..<lowered.endIndex
                let children = Array(lowered[range])
                lowered.removeSubrange(range)
                lowered.append(try build(children))
            }
        }
        guard lowered.count == 1, let expression = lowered.first else {
            throw invalidTraversal(at: path)
        }
        return expression
    }

    private func schedule(
        _ children: [(expression: StateExpr, path: String)],
        at path: String,
        build: @escaping ([CompiledStateExpr]) throws -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        tasks.append(.build(childCount: children.count, path: path, build))
        for child in children.reversed() {
            tasks.append(.expression(child.expression, path: child.path))
        }
    }

    private func scheduleUnary(
        _ value: StateExpr,
        at path: String,
        build: @escaping (CompiledStateExpr) -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        schedule([(value, path)], at: path, build: { build($0[0]) }, on: &tasks)
    }

    private func scheduleBinary(
        _ lhs: StateExpr,
        _ rhs: StateExpr,
        at path: String,
        build: @escaping (CompiledStateExpr, CompiledStateExpr) -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        schedule(
            [(lhs, "\(path).left"), (rhs, "\(path).right")],
            at: path,
            build: { build($0[0], $0[1]) },
            on: &tasks
        )
    }

    private func scheduleBinding(
        _ domain: StateExpr,
        _ body: StateExpr,
        binder: BinderID,
        at path: String,
        build: @escaping (CompiledStateExpr, BinderID, CompiledStateExpr) -> CompiledStateExpr,
        on tasks: inout [StateLoweringTask]
    ) {
        schedule(
            [(domain, "\(path).domain"), (body, "\(path).body")],
            at: path,
            build: { build($0[0], binder, $0[1]) },
            on: &tasks
        )
    }

    private func indexed(_ expressions: [StateExpr], at path: String) -> [(StateExpr, String)] {
        expressions.enumerated().map { ($0.element, "\(path)[\($0.offset)]") }
    }

    private func formalOperatorPlan(
        _ operation: FormalOperator,
        at path: String
    ) throws -> FormalOperatorLoweringPlan {
        switch operation {
        case .reference(_, let arity):
            return .reference(try operatorID(at: path), arity: arity)
        case .lambda(let lambda):
            return .lambda(try lambda.parameters.map { try binder(at: "\(path).parameters.\($0)") })
        }
    }

    private func formalArgumentPlan(
        _ argument: FormalCallArgument,
        at path: String
    ) throws -> FormalArgumentLoweringPlan {
        switch argument {
        case .value: return .value
        case .operator(let operation): return .operator(try formalOperatorPlan(operation, at: path))
        }
    }

    private func formalChildren(
        arguments: [FormalCallArgument],
        at path: String
    ) -> [(StateExpr, String)] {
        var children: [(StateExpr, String)] = []
        for (index, argument) in arguments.enumerated() {
            let argumentPath = "\(path).arguments[\(index)]"
            switch argument {
            case .value(let value): children.append((value, argumentPath))
            case .operator(.lambda(let lambda)): children.append((lambda.body, "\(argumentPath).body"))
            case .operator(.reference): break
            }
        }
        return children
    }

    private func materialize(
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

    private func materialize(
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

    private func child(
        from children: [CompiledStateExpr],
        index: inout Int,
        at path: String
    ) throws -> CompiledStateExpr {
        guard children.indices.contains(index) else { throw invalidTraversal(at: path) }
        let expression = children[index]
        index += 1
        return expression
    }

    private func localOperatorPlans(
        _ operators: [LocalOperator],
        at path: String
    ) throws -> [LocalOperatorLoweringPlan] {
        let declarations = try operators.map { operation in
            (operation, try operatorID(at: "\(path).\(operation.name).declaration"))
        }
        let ids = Set(declarations.map(\.1))
        let calls = Dictionary(uniqueKeysWithValues: declarations.map { _, id in
            (id, bindings.localOperatorDependencies[id, default: []].intersection(ids))
        })
        let recursive = Set(ids.filter { start in
            var pending = Array(calls[start, default: []])
            var visited: Set<OperatorID> = []
            while let current = pending.popLast() {
                if current == start { return true }
                guard visited.insert(current).inserted else { continue }
                pending.append(contentsOf: calls[current, default: []])
            }
            return false
        })
        return try declarations.map { operation, id in
            .init(
                id: id,
                parameters: try operation.parameters.map {
                    try binder(at: "\(path).\(operation.name).parameters.\($0)")
                },
                hasDomain: operation.domain != nil,
                isRecursive: recursive.contains(id)
            )
        }
    }

    private func invalidTraversal(at path: String) -> CompilationDiagnostic {
        .init(
            code: .invalidFormalDeclaration,
            stage: .lowering,
            path: path,
            expected: "one compiled expression for each source expression",
            actual: "the lowering traversal produced an inconsistent expression stack",
            nextSafeAction: "Retain the source model and report this compiler defect."
        )
    }

    private func lower(_ expression: TemporalExpr, at path: String) throws -> CompiledTemporalExpr {
        switch expression {
        case .always(let predicate):
            return .always(try lower(predicate, at: "\(path).body"))
        case .eventually(let predicate):
            return .eventually(try lower(predicate, at: "\(path).body"))
        case .alwaysEventually(let predicate):
            return .alwaysEventually(try lower(predicate, at: "\(path).body"))
        case .eventuallyAlways(let predicate):
            return .eventuallyAlways(try lower(predicate, at: "\(path).body"))
        case .leadsTo(let from, let to):
            return .leadsTo(
                try lower(from, at: "\(path).from"),
                try lower(to, at: "\(path).to")
            )
        }
    }

    private func lower(_ action: ActionExpr, at path: String) throws -> CompiledActionExpr {
        var tasks = [ActionLoweringTask.expression(action, path: path)]
        var lowered: [CompiledActionExpr] = []
        while let task = tasks.popLast() {
            switch task {
            case .build(let childCount, let taskPath, let build):
                guard lowered.count >= childCount else { throw invalidTraversal(at: taskPath) }
                let start = lowered.count - childCount
                let children = Array(lowered[start...])
                lowered.removeSubrange(start...)
                lowered.append(try build(children))
            case .expression(let expression, let taskPath):
                switch expression {
                case .assign(_, let value):
                    lowered.append(try .assign(
                        variable(at: "\(taskPath).assign"),
                        lower(value, at: "\(taskPath).value")
                    ))
                case .unchanged:
                    lowered.append(try .unchanged(variable(at: "\(taskPath).unchanged")))
                case .guard_(let condition):
                    lowered.append(try .guard_(lower(condition, at: "\(taskPath).guard")))
                case .chooseAction(_, let set):
                    lowered.append(try .chooseAction(
                        variable(at: "\(taskPath).choose"),
                        lower(set, at: "\(taskPath).set")
                    ))
                case .existsAction(let name, let set, let body):
                    let binder = try binder(at: "\(taskPath).binder.\(name)")
                    let compiledSet = try lower(set, at: "\(taskPath).set")
                    scheduleAction(
                        [(body, "\(taskPath).body")],
                        at: taskPath,
                        build: { .existsAction(binder, compiledSet, $0[0]) },
                        on: &tasks
                    )
                case .define(let name, let value, let body):
                    let binder = try binder(at: "\(taskPath).binder.\(name)")
                    let compiledValue = try lower(value, at: "\(taskPath).value")
                    scheduleAction(
                        [(body, "\(taskPath).body")],
                        at: taskPath,
                        build: { .define(binder, compiledValue, $0[0]) },
                        on: &tasks
                    )
                case .ifElse(let condition, let then, let otherwise):
                    let compiledCondition = try lower(condition, at: "\(taskPath).condition")
                    scheduleAction(
                        [(then, "\(taskPath).then"), (otherwise, "\(taskPath).else")],
                        at: taskPath,
                        build: { .ifElse(compiledCondition, $0[0], $0[1]) },
                        on: &tasks
                    )
                case .and(let lhs, let rhs):
                    scheduleAction(
                        [(lhs, "\(taskPath).left"), (rhs, "\(taskPath).right")],
                        at: taskPath,
                        build: { .and($0[0], $0[1]) },
                        on: &tasks
                    )
                case .or(let lhs, let rhs):
                    scheduleAction(
                        [(lhs, "\(taskPath).left"), (rhs, "\(taskPath).right")],
                        at: taskPath,
                        build: { .or($0[0], $0[1]) },
                        on: &tasks
                    )
                }
            }
        }
        guard lowered.count == 1, let expression = lowered.first else {
            throw invalidTraversal(at: path)
        }
        return expression
    }

    private func scheduleAction(
        _ children: [(expression: ActionExpr, path: String)],
        at path: String,
        build: @escaping ([CompiledActionExpr]) throws -> CompiledActionExpr,
        on tasks: inout [ActionLoweringTask]
    ) {
        tasks.append(.build(childCount: children.count, path: path, build))
        for child in children.reversed() {
            tasks.append(.expression(child.expression, path: child.path))
        }
    }

    private func lower(
        _ initialization: VariableInitialization,
        at path: String
    ) throws -> CompiledVariableInitialization {
        switch initialization {
        case .value(let value): return .value(.init(formal: value))
        case .expression(let expression): return .expression(try lower(expression, at: path))
        case .memberOf(let set): return .memberOf(try lower(set, at: path))
        }
    }

    private func lower(
        _ parameters: [FormalParameter],
        at path: String
    ) throws -> [CompiledFormalParameter] {
        try parameters.map { parameter in
            switch parameter {
            case .value(let name):
                return .value(try binder(at: "\(path).\(name)"))
            case .operator(let name, let arity):
                return .operator(try operatorID(at: "\(path).\(name)"), arity: arity)
            }
        }
    }

    private func valueReference(at path: String) throws -> CompiledStateExpr {
        switch try reference(at: path) {
        case .variable(let id): return .stateVariable(id)
        case .binder(let id): return .boundValue(id)
        case .controlLocation(let id): return .controlLocation(id)
        case .constant(let value): return .value(value)
        case .operator(let id): return .operatorReference(id)
        case .action, .property, .field: throw diagnostic(path: path)
        }
    }

    private func variable(at path: String) throws -> VariableID {
        guard case .variable(let id) = try reference(at: path) else { throw diagnostic(path: path) }
        return id
    }

    private func binder(at path: String) throws -> BinderID {
        guard case .binder(let id) = try reference(at: path) else { throw diagnostic(path: path) }
        return id
    }

    private func action(at path: String) throws -> ActionID {
        guard case .action(let id) = try reference(at: path) else { throw diagnostic(path: path) }
        return id
    }

    private func property(at path: String) throws -> PropertyID {
        guard case .property(let id) = try reference(at: path) else { throw diagnostic(path: path) }
        return id
    }

    private func controlLocation(at path: String) throws -> ControlLocationID {
        guard case .controlLocation(let id) = try reference(at: path) else { throw diagnostic(path: path) }
        return id
    }

    private func field(at path: String) throws -> FieldID {
        guard case .field(let id) = try reference(at: path) else { throw diagnostic(path: path) }
        return id
    }

    private func operatorID(at path: String) throws -> OperatorID {
        guard case .operator(let id) = try reference(at: path) else { throw diagnostic(path: path) }
        return id
    }

    private func reference(at path: String) throws -> CompiledReference {
        guard let reference = bindings.references[path] else { throw diagnostic(path: path) }
        return reference
    }

    private func diagnostic(path: String) -> CompilationDiagnostic {
        .init(
            code: .unknownReference,
            stage: .lowering,
            path: path,
            expected: "a resolved compiler identity",
            actual: "no binding recorded",
            nextSafeAction: "Compile the source through the binding gate, then lower it."
        )
    }
}
