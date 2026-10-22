private struct InitializationReadEffect: Equatable {
    var variables: Set<VariableID> = []
    var binders: Set<BinderID> = []
    var requiresCompleteState = false

    mutating func formUnion(_ other: Self) {
        variables.formUnion(other.variables)
        binders.formUnion(other.binders)
        requiresCompleteState = requiresCompleteState || other.requiresCompleteState
    }
}

extension CompiledProgram {
    func validateInitializationDependencies() throws {
        var functionEffects = Array(repeating: InitializationReadEffect(), count: functions.count)
        var changed = true
        while changed {
            changed = false
            for (index, function) in functions.enumerated() {
                var effect = try initializationReadEffect(function.body, functionEffects: functionEffects)
                if let guardExpression = function.domainGuard {
                    effect.formUnion(try initializationReadEffect(guardExpression, functionEffects: functionEffects))
                }
                if effect != functionEffects[index] {
                    functionEffects[index] = effect
                    changed = true
                }
            }
        }

        var initialized: Set<VariableID> = []
        for entry in behavior.initializations {
            let expression: CompiledExpression
            switch entry.initialization {
            case .value(let value), .memberOf(let value): expression = value
            }
            let effect = try initializationReadEffect(expression, functionEffects: functionEffects)
            let name = layout.variables.first { $0.id == entry.variable }?.declaration.name ?? "unknown"
            guard !effect.requiresCompleteState else {
                throw CompilationDiagnostic(code: .actionEnablednessInInitializer, stage: .validation,
                    path: "variables.\(name).initialization",
                    expected: "an initializer independent of complete-state checking",
                    actual: "the resolved initializer reads checking state or action enabledness",
                    nextSafeAction: "Initialize from values and previously initialized variables.")
            }
            let unavailable = effect.variables.subtracting(initialized)
            guard unavailable.isEmpty, !initialized.contains(entry.variable) else {
                let missing = unavailable.compactMap { variable in
                    layout.variables.first { $0.id == variable }?.declaration.name
                }.sorted()
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                    path: "variables.\(name).initialization",
                    expected: "a unique initializer reading only previously initialized variables",
                    actual: "unavailable variables \(missing.joined(separator: ", "))",
                    nextSafeAction: "Report this compiler dependency-ordering failure.")
            }
            initialized.insert(entry.variable)
        }
        guard initialized == Set(layout.variables.map(\.id)) else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "variables.initializations",
                expected: "one initializer for every state variable",
                actual: "the resolved initialization plan omits a state variable",
                nextSafeAction: "Report this compiler initialization-plan failure.")
        }
    }

    private func initializationReadEffect(
        _ root: CompiledExpression,
        functionEffects: [InitializationReadEffect]
    ) throws -> InitializationReadEffect {
        var pending: [(expression: CompiledExpression, expanded: Bool)] = [(root, false)]
        var results: [InitializationReadEffect] = []
        while let task = pending.popLast() {
            let expression = task.expression
            if !task.expanded {
                pending.append((expression, true))
                pending.append(contentsOf: expression.children.reversed().map { ($0, false) })
                continue
            }
            let children = Array(results.suffix(expression.children.count))
            results.removeLast(expression.children.count)
            var effect = InitializationReadEffect()
            switch expression.operation {
            case .stateVariable(let variable):
                effect.variables.insert(variable)
            case .boundValue(let binder):
                effect.binders.insert(binder)
            case .enabledAction, .checkingRegister, .setCheckingRegister, .checkingLevel, .checkingDiameter,
                 .nextState, .stutteringStep:
                effect.requiresCompleteState = true
            case .letValue(let binder):
                guard children.count == 2 else { throw CompiledEvaluationError.unresolvedOperator }
                effect = children[1]
                if effect.binders.remove(binder) != nil { effect.formUnion(children[0]) }
            case .call(let id):
                guard functions.indices.contains(id.ordinal), children.count == functions[id.ordinal].parameters.count
                else { throw CompiledEvaluationError.unresolvedOperator }
                effect = functionEffects[id.ordinal]
                let demanded = effect.binders
                effect.binders.subtract(functions[id.ordinal].parameters.map(\.binder))
                for (parameter, argument) in zip(functions[id.ordinal].parameters, children)
                    where demanded.contains(parameter.binder) {
                    effect.formUnion(argument)
                }
            case .operatorReference, .operatorApplication, .checkedCall, .letIn:
                throw CompiledEvaluationError.unresolvedOperator
            default:
                children.forEach { effect.formUnion($0) }
            }
            results.append(effect)
        }
        guard results.count == 1 else { throw CompiledEvaluationError.unresolvedOperator }
        return results[0]
    }
}
