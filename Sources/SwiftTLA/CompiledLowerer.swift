struct CompiledLowerer {
    let bindings: CompiledBindingTable
    let closure: FormalModuleClosure
    let layout: CompiledLayout

    func lower(spec: TLASpec) throws -> CompiledModel {
        var initialValues: [VariableID: CompiledValue] = [:]
        var initializers: [VariableID: CompiledVariableInitializer] = [:]
        for variable in spec.variables {
            guard let id = bindings.variables[variable.name] else {
                throw diagnostic(path: "variables.\(variable.name)")
            }
            initialValues[id] = try initialValue(
                for: variable,
                algorithm: spec.sourceAlgorithms.first?.model.name
            )
            initializers[id] = .init(
                initialSet: try lowerOptional(variable.initialSet, at: "variables.\(variable.name).initialSet"),
                initExpr: try initialExpression(
                    for: variable,
                    algorithm: spec.sourceAlgorithms.first?.model.name
                ),
                lazySet: try lowerOptional(variable.lazySet, at: "variables.\(variable.name).lazySet")
            )
        }
        let sourceAlgorithm = spec.sourceAlgorithms.first?.model.name
        let actions: [CompiledAction] = try spec.actions.map {
            try lower($0, algorithm: sourceAlgorithm)
        }
        let invariants: [CompiledInvariant] = try spec.invariants.map {
            CompiledInvariant(name: $0.name, body: try lower($0.body, at: "invariants.\($0.name).body"))
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
        let localFormalNames = Set(spec.formalOperatorDefinitions.map(\.name))
        let linkedFormalOperators = try closure.resolvedFormalOperatorDefinitions
            .filter { !localFormalNames.contains($0.name) }
            .map { definition in
                CompiledFormalOperatorDefinition(
                    id: try operatorID(at: "linkedFormalOperators.\(definition.name).declaration"),
                    parameters: try lower(definition.parameters, at: "linkedFormalOperators.\(definition.name).parameters"),
                    body: try lower(definition.body, at: "linkedFormalOperators.\(definition.name).body")
                )
            }
        let localRecursiveNames = Set(spec.recursiveFuncs.map(\.name))
        let linkedRecursiveFunctions = try closure.resolvedRecursiveFuncs
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
        return CompiledModel(
            initialValues: initialValues,
            variableInitializers: initializers,
            actions: actions,
            invariants: invariants,
            constraint: try lowerOptional(spec.constraint, at: "constraint"),
            assume: try lowerOptional(spec.assume, at: "assume"),
            formalOperatorDefinitions: formalOperators + linkedFormalOperators,
            recursiveFunctions: recursiveFunctions + linkedRecursiveFunctions,
            symmetrySets: spec.symmetrySets.map { symmetry in
                .init(values: symmetry.values)
            },
            symmetricCollections: spec.symmetricCollections.map {
                .init(members: $0.metadata.members)
            }
        )
    }

    private func lower(_ action: NamedAction, algorithm: String?) throws -> CompiledAction {
        guard let id = bindings.actions[action.name] else {
            throw diagnostic(path: "actions.\(action.name)")
        }
        return CompiledAction(
            id: id,
            bindings: try action.bindings.map {
                CompiledActionBinding(
                    binder: try binder(at: "actions.\(action.name).bindings.\($0.name)"),
                    values: $0.values
                )
            },
            body: try lower(
                action.body,
                at: "actions.\(action.name).body",
                controlOwner: layout.controlOwner(forActionNamed: action.name),
                algorithm: algorithm
            )
        )
    }

    private func lowerOptional(_ expression: StateExpr?, at path: String) throws -> CompiledStateExpr? {
        guard let expression else { return nil }
        let source: StateExpr = expression
        return try lower(source, at: path)
    }

    private func lower(_ expression: StateExpr, at path: String) throws -> CompiledStateExpr {
        switch expression {
        case .value(let value): return .value(value)
        case .variable: return try valueReference(at: path)
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
        case .add(let lhs, let rhs): return try binary(CompiledStateExpr.add, lhs, rhs, path)
        case .subtract(let lhs, let rhs): return try binary(CompiledStateExpr.subtract, lhs, rhs, path)
        case .multiply(let lhs, let rhs): return try binary(CompiledStateExpr.multiply, lhs, rhs, path)
        case .divide(let lhs, let rhs): return try binary(CompiledStateExpr.divide, lhs, rhs, path)
        case .modulo(let lhs, let rhs): return try binary(CompiledStateExpr.modulo, lhs, rhs, path)
        case .integerDivide(let lhs, let rhs): return try binary(CompiledStateExpr.integerDivide, lhs, rhs, path)
        case .equal(let lhs, let rhs): return try binary(CompiledStateExpr.equal, lhs, rhs, path)
        case .notEqual(let lhs, let rhs): return try binary(CompiledStateExpr.notEqual, lhs, rhs, path)
        case .lessThan(let lhs, let rhs): return try binary(CompiledStateExpr.lessThan, lhs, rhs, path)
        case .lessOrEqual(let lhs, let rhs): return try binary(CompiledStateExpr.lessOrEqual, lhs, rhs, path)
        case .greaterThan(let lhs, let rhs): return try binary(CompiledStateExpr.greaterThan, lhs, rhs, path)
        case .greaterOrEqual(let lhs, let rhs): return try binary(CompiledStateExpr.greaterOrEqual, lhs, rhs, path)
        case .and(let lhs, let rhs): return try binary(CompiledStateExpr.and, lhs, rhs, path)
        case .or(let lhs, let rhs): return try binary(CompiledStateExpr.or, lhs, rhs, path)
        case .in(let lhs, let rhs): return try binary(CompiledStateExpr.in, lhs, rhs, path)
        case .subset(let lhs, let rhs): return try binary(CompiledStateExpr.subset, lhs, rhs, path)
        case .union(let lhs, let rhs): return try binary(CompiledStateExpr.union, lhs, rhs, path)
        case .intersection(let lhs, let rhs): return try binary(CompiledStateExpr.intersection, lhs, rhs, path)
        case .setDifference(let lhs, let rhs): return try binary(CompiledStateExpr.setDifference, lhs, rhs, path)
        case .tupleDynamicAccess(let lhs, let rhs): return try binary(CompiledStateExpr.tupleDynamicAccess, lhs, rhs, path)
        case .tupleAppend(let lhs, let rhs): return try binary(CompiledStateExpr.tupleAppend, lhs, rhs, path)
        case .tupleConcatenate(let lhs, let rhs): return try binary(CompiledStateExpr.tupleConcatenate, lhs, rhs, path)
        case .functionApply(let lhs, let rhs): return try binary(CompiledStateExpr.functionApply, lhs, rhs, path)
        case .functionSet(let lhs, let rhs): return try binary(CompiledStateExpr.functionSet, lhs, rhs, path)
        case .setSum(let lhs, let rhs): return try binary(CompiledStateExpr.setSum, lhs, rhs, path)
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
            return .recordLiteral(try fields.reduce(into: [String: CompiledStateExpr]()) { result, item in
                result[item.key] = try lower(item.value, at: "\(path).\(item.key)")
            })
        case .recordAccess(let value, let field): return try .recordAccess(lower(value, at: path), field)
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
            return try .letIn(
                operators.map { try lower($0, at: "\(path).\($0.name)") },
                lower(body, at: "\(path).body")
            )
        }
    }

    private func lower(
        _ action: ActionExpr,
        at path: String,
        controlOwner: ControlOwner?,
        algorithm: String?
    ) throws -> CompiledActionExpr {
        switch action {
        case .assign(let name, let value):
            let variable = try variable(at: "\(path).assign")
            let compiledValue = name == "pc" || name == "stack"
                ? try lowerControlValue(
                    value,
                    at: "\(path).value",
                    owner: controlOwner,
                    algorithm: algorithm,
                    stackFrame: name == "stack"
                )
                : try lower(value, at: "\(path).value")
            return .assign(variable, compiledValue)
        case .unchanged: return try .unchanged(variable(at: "\(path).unchanged"))
        case .guard_(let condition):
            return try .guard_(lowerControlGuard(condition, at: "\(path).guard", owner: controlOwner, algorithm: algorithm))
        case .chooseAction(_, let set): return try .chooseAction(variable(at: "\(path).choose"), lower(set, at: "\(path).set"))
        case .existsAction(let name, let set, let body):
            return try .existsAction(
                binder(at: "\(path).binder.\(name)"),
                lower(set, at: "\(path).set"),
                lower(body, at: "\(path).body", controlOwner: controlOwner, algorithm: algorithm)
            )
        case .define(let name, let value, let body):
            return try .define(
                binder(at: "\(path).binder.\(name)"),
                lower(value, at: "\(path).value"),
                lower(body, at: "\(path).body", controlOwner: controlOwner, algorithm: algorithm)
            )
        case .ifElse(let condition, let then, let otherwise):
            return try .ifElse(
                lowerControlGuard(condition, at: "\(path).condition", owner: controlOwner, algorithm: algorithm),
                lower(then, at: "\(path).then", controlOwner: controlOwner, algorithm: algorithm),
                lower(otherwise, at: "\(path).else", controlOwner: controlOwner, algorithm: algorithm)
            )
        case .and(let lhs, let rhs):
            return try .and(
                lower(lhs, at: "\(path).left", controlOwner: controlOwner, algorithm: algorithm),
                lower(rhs, at: "\(path).right", controlOwner: controlOwner, algorithm: algorithm)
            )
        case .or(let lhs, let rhs):
            return try .or(
                lower(lhs, at: "\(path).left", controlOwner: controlOwner, algorithm: algorithm),
                lower(rhs, at: "\(path).right", controlOwner: controlOwner, algorithm: algorithm)
            )
        }
    }

    private func initialValue(
        for variable: NamedVar,
        algorithm: String?
    ) throws -> CompiledValue {
        guard variable.name == "pc" else {
            return .init(formal: variable.initial)
        }
        return try controlValue(variable.initial, owner: nil, algorithm: algorithm)
    }

    private func initialExpression(
        for variable: NamedVar,
        algorithm: String?
    ) throws -> CompiledStateExpr? {
        guard let expression = variable.initExpr else { return nil }
        guard variable.name == "pc" else {
            return try lower(expression, at: "variables.\(variable.name).initExpr")
        }
        return try lowerControlValue(
            expression,
            at: "variables.\(variable.name).initExpr",
            owner: nil,
            algorithm: algorithm
        )
    }

    private func controlValue(
        _ value: TLAValue,
        owner: ControlOwner?,
        algorithm: String?
    ) throws -> CompiledValue {
        switch value {
        case .string(let name):
            guard let label = layout.controlLabelID(named: name, owner: owner, algorithm: algorithm) else {
                throw controlLabelDiagnostic(name: name)
            }
            return .controlLabel(label)
        case .set(let values):
            return .set(try Set(values.map { try controlValue($0, owner: owner, algorithm: algorithm) }))
        case .tuple(let values):
            return .tuple(try values.map { try controlValue($0, owner: owner, algorithm: algorithm) })
        case .record(let values):
            return .record(try values.reduce(into: [:]) { result, entry in
                result[entry.key] = entry.key == "pc"
                    ? try controlValue(entry.value, owner: owner, algorithm: algorithm)
                    : .init(formal: entry.value)
            })
        case .function(let values):
            return .function(try values.reduce(into: [:]) { result, entry in
                result[.init(formal: entry.key)] = try controlValue(entry.value, owner: owner, algorithm: algorithm)
            })
        default:
            return .init(formal: value)
        }
    }

    private func lowerControlValue(
        _ expression: StateExpr,
        at path: String,
        owner: ControlOwner?,
        algorithm: String?,
        stackFrame: Bool = false
    ) throws -> CompiledStateExpr {
        switch expression {
        case .value(.string(let name)):
            guard let label = layout.controlLabelID(named: name, owner: owner, algorithm: algorithm) else {
                throw controlLabelDiagnostic(name: name)
            }
            return .controlLabel(label)
        case .tupleLiteral(let values):
            return .tupleLiteral(try values.enumerated().map { index, value in
                try lowerControlValue(
                    value,
                    at: "\(path)[\(index)]",
                    owner: owner,
                    algorithm: algorithm,
                    stackFrame: stackFrame
                )
            })
        case .recordLiteral(let fields):
            return .recordLiteral(try fields.reduce(into: [:]) { result, field in
                if stackFrame, field.key == "pc" {
                    result[field.key] = try lowerControlValue(
                        field.value,
                        at: "\(path).\(field.key)",
                        owner: owner,
                        algorithm: algorithm
                    )
                } else if stackFrame {
                    result[field.key] = try lower(field.value, at: "\(path).\(field.key)")
                } else {
                    result[field.key] = try lowerControlValue(
                        field.value,
                        at: "\(path).\(field.key)",
                        owner: owner,
                        algorithm: algorithm
                    )
                }
            })
        case .functionLiteral(let domain, let binder, let body):
            return .functionLiteral(
                try lower(domain, at: "\(path).domain"),
                try self.binder(at: "\(path).binder.\(binder)"),
                try lowerControlValue(body, at: "\(path).body", owner: owner, algorithm: algorithm, stackFrame: stackFrame)
            )
        case .except(let function, let key, let replacement):
            return .except(
                try lower(function, at: "\(path).function"),
                try lower(key, at: "\(path).key"),
                try lowerControlValue(replacement, at: "\(path).replacement", owner: owner, algorithm: algorithm, stackFrame: stackFrame)
            )
        default:
            return try lower(expression, at: path)
        }
    }

    private func lowerControlGuard(
        _ expression: StateExpr,
        at path: String,
        owner: ControlOwner?,
        algorithm: String?
    ) throws -> CompiledStateExpr {
        switch expression {
        case .equal(let lhs, let rhs) where isControlReference(lhs):
            return .equal(
                try lower(lhs, at: "\(path).left"),
                try lowerControlValue(rhs, at: "\(path).right", owner: owner, algorithm: algorithm)
            )
        case .equal(let lhs, let rhs) where isControlReference(rhs):
            return .equal(
                try lowerControlValue(lhs, at: "\(path).left", owner: owner, algorithm: algorithm),
                try lower(rhs, at: "\(path).right")
            )
        case .notEqual(let lhs, let rhs) where isControlReference(lhs):
            return .notEqual(
                try lower(lhs, at: "\(path).left"),
                try lowerControlValue(rhs, at: "\(path).right", owner: owner, algorithm: algorithm)
            )
        case .notEqual(let lhs, let rhs) where isControlReference(rhs):
            return .notEqual(
                try lowerControlValue(lhs, at: "\(path).left", owner: owner, algorithm: algorithm),
                try lower(rhs, at: "\(path).right")
            )
        default:
            return try lower(expression, at: path)
        }
    }

    private func isControlReference(_ expression: StateExpr) -> Bool {
        switch expression {
        case .variable("pc"), .functionApply(.variable("pc"), _):
            return true
        default:
            return false
        }
    }

    private func controlLabelDiagnostic(name: String) -> CompilationDiagnostic {
        .init(
            code: .unknownControlLabel,
            stage: .binding,
            path: "controlLabels.\(name)",
            expected: "a control label declared by the source algorithm",
            actual: "no matching control label",
            nextSafeAction: "Use a label declared by this algorithm, then compile again."
        )
    }

    private func lower(_ operation: LocalOperator, at path: String) throws -> CompiledLocalOperator {
        .init(
            id: try operatorID(at: "\(path).declaration"),
            parameters: try operation.parameters.map { try binder(at: "\(path).parameters.\($0)") },
            domain: try lowerOptional(operation.domain, at: "\(path).domain"),
            body: try lower(operation.body, at: "\(path).body")
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

    private func binary(
        _ make: (CompiledStateExpr, CompiledStateExpr) -> CompiledStateExpr,
        _ lhs: StateExpr,
        _ rhs: StateExpr,
        _ path: String
    ) throws -> CompiledStateExpr {
        try make(lower(lhs, at: "\(path).left"), lower(rhs, at: "\(path).right"))
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
        case .constant(let value): return .value(value)
        case .operator(let id): return .operatorReference(id)
        case .action: throw diagnostic(path: path)
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
