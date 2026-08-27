private enum StateLoweringTask {
    case expression(StateExpr, path: String)
    case binary((CompiledStateExpr, CompiledStateExpr) -> CompiledStateExpr, path: String)
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
                let operation: ((CompiledStateExpr, CompiledStateExpr) -> CompiledStateExpr)?
                let operands: (StateExpr, StateExpr)?
                switch expression {
                case .add(let lhs, let rhs): operation = CompiledStateExpr.add; operands = (lhs, rhs)
                case .subtract(let lhs, let rhs): operation = CompiledStateExpr.subtract; operands = (lhs, rhs)
                case .multiply(let lhs, let rhs): operation = CompiledStateExpr.multiply; operands = (lhs, rhs)
                case .divide(let lhs, let rhs): operation = CompiledStateExpr.divide; operands = (lhs, rhs)
                case .modulo(let lhs, let rhs): operation = CompiledStateExpr.modulo; operands = (lhs, rhs)
                case .integerDivide(let lhs, let rhs): operation = CompiledStateExpr.integerDivide; operands = (lhs, rhs)
                case .equal(let lhs, let rhs): operation = CompiledStateExpr.equal; operands = (lhs, rhs)
                case .notEqual(let lhs, let rhs): operation = CompiledStateExpr.notEqual; operands = (lhs, rhs)
                case .lessThan(let lhs, let rhs): operation = CompiledStateExpr.lessThan; operands = (lhs, rhs)
                case .lessOrEqual(let lhs, let rhs): operation = CompiledStateExpr.lessOrEqual; operands = (lhs, rhs)
                case .greaterThan(let lhs, let rhs): operation = CompiledStateExpr.greaterThan; operands = (lhs, rhs)
                case .greaterOrEqual(let lhs, let rhs): operation = CompiledStateExpr.greaterOrEqual; operands = (lhs, rhs)
                case .and(let lhs, let rhs): operation = CompiledStateExpr.and; operands = (lhs, rhs)
                case .or(let lhs, let rhs): operation = CompiledStateExpr.or; operands = (lhs, rhs)
                case .in(let lhs, let rhs): operation = CompiledStateExpr.in; operands = (lhs, rhs)
                case .subset(let lhs, let rhs): operation = CompiledStateExpr.subset; operands = (lhs, rhs)
                case .union(let lhs, let rhs): operation = CompiledStateExpr.union; operands = (lhs, rhs)
                case .intersection(let lhs, let rhs): operation = CompiledStateExpr.intersection; operands = (lhs, rhs)
                case .setDifference(let lhs, let rhs): operation = CompiledStateExpr.setDifference; operands = (lhs, rhs)
                case .tupleDynamicAccess(let lhs, let rhs): operation = CompiledStateExpr.tupleDynamicAccess; operands = (lhs, rhs)
                case .tupleAppend(let lhs, let rhs): operation = CompiledStateExpr.tupleAppend; operands = (lhs, rhs)
                case .tupleConcatenate(let lhs, let rhs): operation = CompiledStateExpr.tupleConcatenate; operands = (lhs, rhs)
                case .functionApply(let lhs, let rhs): operation = CompiledStateExpr.functionApply; operands = (lhs, rhs)
                case .functionSet(let lhs, let rhs): operation = CompiledStateExpr.functionSet; operands = (lhs, rhs)
                case .setSum(let lhs, let rhs): operation = CompiledStateExpr.setSum; operands = (lhs, rhs)
                default: operation = nil; operands = nil
                }
                if let operation, let operands {
                    tasks.append(.binary(operation, path: path))
                    tasks.append(.expression(operands.1, path: "\(path).right"))
                    tasks.append(.expression(operands.0, path: "\(path).left"))
                } else {
                    lowered.append(try lowerRecursive(expression, at: path))
                }
            case .binary(let operation, let path):
                guard lowered.count >= 2 else { throw invalidTraversal(at: path) }
                let rhs = lowered.removeLast()
                let lhs = lowered.removeLast()
                lowered.append(operation(lhs, rhs))
            }
        }
        guard lowered.count == 1, let expression = lowered.first else {
            throw invalidTraversal(at: path)
        }
        return expression
    }

    private func lowerRecursive(_ expression: StateExpr, at path: String) throws -> CompiledStateExpr {
        switch expression {
        case .sourceIssue(let issue):
            throw issue.compilationDiagnostic(stage: .lowering, path: path)
        case .value(let value): return .value(value)
        case .currentProcess:
            throw diagnostic(path: path)
        case .programCounter, .procedureStack: return try valueReference(at: path)
        case .controlLocation: return .controlLocation(try controlLocation(at: path))
        case .variable: return try valueReference(at: path)
        case .processLocalFamily:
            throw diagnostic(path: path)
        case .enabledAction: return .enabledAction(try action(at: path))
        case .negate(let value): return .negate(try lower(value, at: path))
        case .not(let value): return .not(try lower(value, at: path))
        case .cardinality(let value): return .cardinality(try lower(value, at: path))
        case .powerSet(let value): return .powerSet(try lower(value, at: path))
        case .unionAll(let value): return .unionAll(try lower(value, at: path))
        case .tupleLength(let value): return .tupleLength(try lower(value, at: path))
        case .tupleHead(let value): return .tupleHead(try lower(value, at: path))
        case .tupleTail(let value): return .tupleTail(try lower(value, at: path))
        case .domain(let value): return .domain(try lower(value, at: path))
        case .sequenceFromSet(let value): return .sequenceFromSet(try lower(value, at: path))
        case .add, .subtract, .multiply, .divide, .modulo, .integerDivide,
             .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
             .and, .or, .in, .subset, .union, .intersection, .setDifference,
             .tupleDynamicAccess, .tupleAppend, .tupleConcatenate,
             .functionApply, .functionSet, .setSum:
            throw invalidTraversal(at: path)
        case .ifThenElse(let condition, let then, let otherwise):
            return try .ifThenElse(
                lower(condition, at: "\(path).condition"),
                lower(then, at: "\(path).then"),
                lower(otherwise, at: "\(path).else")
            )
        case .setLiteral(let values): return try .setLiteral(lower(values, at: path))
        case .tupleLiteral(let values): return try .tupleLiteral(lower(values, at: path))
        case .tupleAccess(let value, let index): return try .tupleAccess(lower(value, at: path), index)
        case .recordLiteral(let fields):
            return try .recordLiteral(.init(fields.fields.enumerated().map { index, item in
                let fieldPath = "\(path).fields[\(index)]"
                return .init(
                    id: try field(at: "\(fieldPath).declaration"),
                    key: .string(item.name),
                    value: try lower(item.value, at: "\(fieldPath).value")
                )
            }))
        case .recordAccess(let value, let field):
            return try .recordAccess(
                lower(value, at: "\(path).value"),
                self.field(at: "\(path).field"),
                .string(field)
            )
        case .except(let function, let key, let value):
            return try .except(
                lower(function, at: "\(path).function"),
                lower(key, at: "\(path).key"),
                lower(value, at: "\(path).value")
            )
        case .caseExpr(let pairs, let otherwise):
            return .caseExpr(try lower(pairs, at: "\(path).branch"), try lowerOptional(otherwise, at: "\(path).otherwise"))
        case .setFilter(let set, let name, let predicate):
            return try binding(CompiledStateExpr.setFilter, set, name, predicate, path)
        case .setMap(let value, let name, let set):
            return try .setMap(lower(value, at: "\(path).body"), binder(at: "\(path).binder.\(name)"), lower(set, at: "\(path).domain"))
        case .functionLiteral(let domain, let name, let body):
            return try binding(CompiledStateExpr.functionLiteral, domain, name, body, path)
        case .forAll(let set, let name, let predicate): return try binding(CompiledStateExpr.forAll, set, name, predicate, path)
        case .exists(let set, let name, let predicate): return try binding(CompiledStateExpr.exists, set, name, predicate, path)
        case .choose(let set, let name, let predicate): return try binding(CompiledStateExpr.choose, set, name, predicate, path)
        case .integerRange(let lowerBound, let upperBound):
            return try .integerRange(
                lower(lowerBound, at: "\(path).lower"),
                lower(upperBound, at: "\(path).upper")
            )
        case .foldFunction(let lambda, let initial, let sequence):
            return try .foldFunction(
                lower(lambda, at: path),
                initial: lower(initial, at: "\(path).initial"),
                sequence: lower(sequence, at: "\(path).sequence")
            )
        case .operatorApplication(let operation, let arguments):
            return try .operatorApplication(
                lower(operation, at: "\(path).operator"),
                arguments.enumerated().map { index, argument in try lower(argument, at: "\(path).arguments[\(index)]") }
            )
        case .recursiveCall(_, let arguments):
            return try .recursiveCall(try operatorID(at: path), arguments.enumerated().map { index, argument in
                try lower(argument, at: "\(path).arguments[\(index)]")
            })
        case .letValue(let name, let value, let body):
            return try .letValue(
                binder(at: "\(path).binder.\(name)"),
                lower(value, at: "\(path).value"),
                lower(body, at: "\(path).body")
            )
        case .letIn(let operators, let body):
            let localOperators = try operators.map { operation in
                (operation, try operatorID(at: "\(path).\(operation.name).declaration"))
            }
            let localOperatorIDs = Set(localOperators.map(\.1))
            let calls = Dictionary(uniqueKeysWithValues: localOperators.map { _, id in
                (id, bindings.localOperatorDependencies[id, default: []].intersection(localOperatorIDs))
            })
            func isRecursive(_ start: OperatorID, from current: OperatorID, visited: Set<OperatorID>) -> Bool {
                for target in calls[current, default: []] {
                    if target == start { return true }
                    if !visited.contains(target), isRecursive(start, from: target, visited: visited.union([target])) {
                        return true
                    }
                }
                return false
            }
            let recursiveOperatorIDs = Set(localOperatorIDs.filter {
                isRecursive($0, from: $0, visited: [$0])
            })
            return try .letIn(
                operators.map {
                    try lower(
                        $0,
                        at: "\(path).\($0.name)",
                        isRecursive: recursiveOperatorIDs.contains(
                            try operatorID(at: "\(path).\($0.name).declaration")
                        )
                    )
                },
                lower(body, at: "\(path).body")
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
        switch action {
        case .assign(_, let value):
            let variable = try variable(at: "\(path).assign")
            return try .assign(variable, lower(value, at: "\(path).value"))
        case .unchanged: return try .unchanged(variable(at: "\(path).unchanged"))
        case .guard_(let condition): return try .guard_(lower(condition, at: "\(path).guard"))
        case .chooseAction(_, let set): return try .chooseAction(variable(at: "\(path).choose"), lower(set, at: "\(path).set"))
        case .existsAction(let name, let set, let body):
            return try .existsAction(
                binder(at: "\(path).binder.\(name)"),
                lower(set, at: "\(path).set"),
                lower(body, at: "\(path).body")
            )
        case .define(let name, let value, let body):
            return try .define(
                binder(at: "\(path).binder.\(name)"),
                lower(value, at: "\(path).value"),
                lower(body, at: "\(path).body")
            )
        case .ifElse(let condition, let then, let otherwise):
            return try .ifElse(
                lower(condition, at: "\(path).condition"),
                lower(then, at: "\(path).then"),
                lower(otherwise, at: "\(path).else")
            )
        case .and(let lhs, let rhs):
            return try .and(
                lower(lhs, at: "\(path).left"),
                lower(rhs, at: "\(path).right")
            )
        case .or(let lhs, let rhs):
            return try .or(
                lower(lhs, at: "\(path).left"),
                lower(rhs, at: "\(path).right")
            )
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
        _ operation: LocalOperator,
        at path: String,
        isRecursive: Bool
    ) throws -> CompiledLocalOperator {
        .init(
            id: try operatorID(at: "\(path).declaration"),
            parameters: try operation.parameters.map { try binder(at: "\(path).parameters.\($0)") },
            domain: try lowerOptional(operation.domain, at: "\(path).domain"),
            body: try lower(operation.body, at: "\(path).body"),
            isRecursive: isRecursive
        )
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

    private func lower(_ lambda: FormalLambda, at path: String) throws -> CompiledFormalLambda {
        .init(
            parameters: try lambda.parameters.map { try binder(at: "\(path).parameters.\($0)") },
            body: try lower(lambda.body, at: "\(path).body")
        )
    }

    private func lower(_ operation: FormalOperator, at path: String) throws -> CompiledFormalOperator {
        switch operation {
        case .reference(_, let arity): return try .reference(operatorID(at: path), arity: arity)
        case .lambda(let lambda): return .lambda(try lower(lambda, at: path))
        }
    }

    private func lower(_ argument: FormalCallArgument, at path: String) throws -> CompiledFormalCallArgument {
        switch argument {
        case .value(let value): return .value(try lower(value, at: path))
        case .operator(let operation): return .operator(try lower(operation, at: path))
        }
    }

    private func lower(_ values: [StateExpr], at path: String) throws -> [CompiledStateExpr] {
        try values.enumerated().map { index, value in try lower(value, at: "\(path)[\(index)]") }
    }

    private func binding(
        _ make: (CompiledStateExpr, BinderID, CompiledStateExpr) -> CompiledStateExpr,
        _ domain: StateExpr,
        _ name: String,
        _ body: StateExpr,
        _ path: String
    ) throws -> CompiledStateExpr {
        try make(
            lower(domain, at: "\(path).domain"),
            binder(at: "\(path).binder.\(name)"),
            lower(body, at: "\(path).body")
        )
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
