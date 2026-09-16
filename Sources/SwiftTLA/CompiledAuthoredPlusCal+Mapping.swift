extension CompiledAuthoredPlusCalAlgorithmPlan {
    func map(_ transform: (CompiledExpression) throws -> CompiledExpression) rethrows -> Self {
        func state(_ declaration: CompiledAuthoredPlusCalState) throws -> CompiledAuthoredPlusCalState {
            let initialization: CompiledAuthoredPlusCalState.Initialization
            switch declaration.initialization {
            case .expression(let value): initialization = .expression(try transform(value))
            case .memberOf(let domain): initialization = .memberOf(try transform(domain))
            }
            return .init(variable: declaration.variable, initialization: initialization)
        }
        func target(_ value: CompiledAuthoredPlusCalLValue) throws -> CompiledAuthoredPlusCalLValue {
            switch value {
            case .root: return value
            case .function(let base, let key): return .function(base: try target(base), key: try transform(key))
            case .field(let base, let name): return .field(try target(base), name)
            }
        }
        func statement(_ value: CompiledAuthoredPlusCalStatement) throws -> CompiledAuthoredPlusCalStatement {
            switch value {
            case .when(let value): return .when(try transform(value))
            case .assert(let value): return .assert(try transform(value))
            case .set(let location, let value): return .set(target: try target(location), value: try transform(value))
            case .parallel(let assignments):
                return .parallel(try assignments.map { .init(target: try target($0.target), value: try transform($0.value)) })
            case .letBinding(let binder, let value, let body):
                return .letBinding(variable: binder, value: try transform(value), try body.map(statement))
            case .with(let binder, let domain, let body):
                return .with(variable: binder, source: try transform(domain), try body.map(statement))
            case .ifElse(let condition, let yes, let no):
                return .ifElse(try transform(condition), try yes.map(statement), try no.map(statement))
            case .either(let left, let right): return .either(try left.map(statement), try right.map(statement))
            case .call(let procedure, let arguments): return .call(target: procedure, arguments: try arguments.map(transform))
            case .goto, .return, .skip: return value
            }
        }
        func step(_ value: CompiledAuthoredPlusCalStep) throws -> CompiledAuthoredPlusCalStep {
            try .init(label: value.label, statements: value.statements.map(statement), loopCondition: value.loopCondition.map(transform))
        }
        return try .init(name: name, sequentialFairness: sequentialFairness,
            shared: shared.map(state), procedures: procedures.map {
                try .init(id: $0.id, parameters: $0.parameters, parameterVariables: $0.parameterVariables,
                    locals: $0.locals.map(state), steps: $0.steps.map(step))
            }, processes: processes.map {
                try .init(name: $0.name, binder: $0.binder, swiftType: $0.swiftType,
                    domain: transform($0.domain), fairness: $0.fairness, locals: $0.locals.map(state), steps: $0.steps.map(step))
            }, sequentialSteps: sequentialSteps.map(step), properties: properties,
            translatorOwnedPropertyNames: translatorOwnedPropertyNames)
    }
}
