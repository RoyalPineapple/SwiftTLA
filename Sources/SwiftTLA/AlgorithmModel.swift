package struct AlgorithmModel: Sendable {
    package let name: String
    package let sequentialFairness: SequentialAlgorithmFairness
    package let components: [AlgorithmComponentModel]

    package init(
        name: String,
        sequentialFairness: SequentialAlgorithmFairness = .none,
        components: [AlgorithmComponentModel]
    ) {
        self.name = name
        self.sequentialFairness = sequentialFairness
        self.components = components
    }

    var processes: [AlgorithmProcessModel] {
        components.compactMap {
            guard case .process(let process) = $0 else { return nil }
            return process
        }
    }

    /// A PlusCal `begin ... end algorithm` body has one scalar program
    /// counter. Keep it distinct from a one-member `Each` process, whose
    /// counter is a function and whose transition labels carry a parameter.
    var sequentialSteps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }

    var procedures: [AlgorithmProcedureModel] {
        components.compactMap {
            guard case .procedure(let procedure) = $0 else { return nil }
            return procedure
        }
    }

    var formalOperatorDefinitions: [FormalOperatorDefinition] {
        components.compactMap {
            guard case .formalOperator(let definition) = $0 else { return nil }
            return definition
        }
    }

    var authoredIdentifiers: Set<String> {
        func collect(_ components: [AlgorithmComponentModel], into names: inout Set<String>) {
            for component in components {
                switch component {
                case .shared(let declaration), .local(let declaration):
                    names.insert(declaration.root)
                case .step(let step):
                    names.insert(step.label.name)
                    names.formUnion(step.statements.algorithmScopeNames)
                case .process(let process):
                    collect(process.components, into: &names)
                case .procedure(let procedure):
                    names.insert(procedure.name)
                    procedure.parameters.forEach { names.insert($0.root) }
                    procedure.locals.forEach { names.insert($0.root) }
                    procedure.steps.forEach {
                        names.insert($0.label.name)
                        names.formUnion($0.statements.algorithmScopeNames)
                    }
                case .invariant(let invariant):
                    names.insert(invariant.name)
                case .temporal(let temporal):
                    names.insert(temporal.name)
                case .formalOperator(let definition):
                    names.insert(definition.name)
                case .stateConstraint, .invalidPlacement:
                    continue
                }
            }
        }

        var names: Set<String> = ["self"]
        collect(components, into: &names)
        return names
    }

    /// Resolves ordered reads and writes before execution and export diverge.
    func resolvingAtomicSteps() -> AlgorithmModel {
        var usedBindings = authoredIdentifiers
        var nextBinding = 0

        func binding() -> String {
            while true {
                let candidate = "__atomic_\(nextBinding)"
                nextBinding += 1
                if usedBindings.insert(candidate).inserted {
                    return candidate
                }
            }
        }

        // Snapshot each write where it occurs, then publish one assignment per
        // root at the end of the atomic branch. PlusCal labels require that form.
        func schedule(
            _ values: [AlgorithmStatementModel],
            assignments: [AlgorithmAssignmentModel] = [],
            replacements: [String: StateExpr] = [:]
        ) -> [AlgorithmStatementModel] {
            let finalWrites = assignments.isEmpty ? [] : [AlgorithmStatementModel.parallel(assignments)]
            guard let statement = values.first else { return finalWrites }
            let suffix = Array(values.dropFirst())
            func expression(_ value: StateExpr) -> StateExpr {
                StateExpr.substituteVariables(replacements, in: value)
            }
            func continued(_ body: [AlgorithmStatementModel]) -> [AlgorithmStatementModel] {
                schedule(body + suffix, assignments: assignments, replacements: replacements)
            }
            switch statement {
            case .set(let target, let value):
                let name = binding()
                let updated: StateExpr
                switch target {
                case .root: updated = expression(value)
                case .function(let root, let key):
                    updated = expression(.except(.variable(root), key, value))
                }
                let pending = assignments.filter { $0.target.root != target.root }
                    + [.init(target: .root(target.root), value: .variable(name))]
                var next = replacements
                next[target.root] = .variable(name)
                return [.letBinding(variable: name, value: updated,
                    schedule(suffix, assignments: pending, replacements: next))]
            case .when, .assert, .skip, .rejected:
                return [statement.mappingExpressions(expression)] + continued([])
            case .letBinding(let variable, let value, let body):
                let name = binding()
                let renamed = body.map {
                    $0.substitutingVariable(variable, with: .variable(name), assignmentTargets: .replaceWhenVariable)
                }
                return [.letBinding(variable: name, value: expression(value), continued(renamed))]
            case .with(let variable, let source, let body):
                let name = binding()
                let renamed = body.map {
                    $0.substitutingVariable(variable, with: .variable(name), assignmentTargets: .replaceWhenVariable)
                }
                return [.with(variable: name, source: expression(source), continued(renamed))]
            case .choose(let variable, let domain, let body):
                return continued([.with(variable: variable,
                    source: .setLiteral(domain.map(StateExpr.value)), body)])
            case .ifElse(let condition, let then, let otherwise):
                return [.ifElse(expression(condition), continued(then), continued(otherwise))]
            case .either(let first, let second):
                return [.either(continued(first), continued(second))]
            case .stop:
                return finalWrites + [.stop]
            case .goto, .return:
                return finalWrites + [statement]
            case .call:
                return finalWrites + [statement.mappingExpressions(expression)] + suffix
            case .parallel:
                preconditionFailure("Atomic statements must only be scheduled once")
            }
        }

        func component(_ value: AlgorithmComponentModel) -> AlgorithmComponentModel {
            switch value {
            case .step(let step):
                return .step(.init(label: step.label, statements: schedule(step.statements),
                    loopCondition: step.loopCondition))
            case .process(let process):
                return .process(.init(typeName: process.typeName, domain: process.domain,
                    fairness: process.fairness, components: process.components.map(component)))
            case .procedure(let procedure):
                return .procedure(.init(name: procedure.name, parameters: procedure.parameters,
                    components: procedure.components.map(component)))
            default:
                return value
            }
        }
        return .init(name: name, sequentialFairness: sequentialFairness,
            components: components.map(component))
    }

    func plusCalProjection() -> AlgorithmModel {
        let localRoots: Set<String> = Set(processes.flatMap { process in
            process.components.compactMap { component in
                guard case .local(let declaration) = component else { return nil }
                return declaration.root
            }
        })
        func lowerAnonymousLambdas(_ value: StateExpr) -> StateExpr {
            StateExpr.renamingRecursiveCalls(
                in: value,
                using: { $0 },
                lowerAnonymousLambdaApplications: true
            )
        }

        func expression(_ value: StateExpr) -> StateExpr {
            let family = localRoots.reduce(value) { projectedExpression, root in
                projectedExpression.replacingProcessLocalFamily(named: root, with: .variable(root))
            }
            return lowerAnonymousLambdas(family.replacingCurrentProcess(with: .variable("self")))
        }

        func initialization(_ value: VariableInitialization) -> VariableInitialization {
            switch value {
            case .value: return value
            case .expression(let initial): return .expression(expression(initial))
            case .memberOf(let set): return .memberOf(expression(set))
            }
        }

        func state(_ value: AlgorithmStateModel) -> AlgorithmStateModel {
            .init(
                root: value.root,
                initialization: initialization(value.initialization),
                swiftTypeName: value.swiftTypeName
            )
        }

        func statements(_ values: [AlgorithmStatementModel]) -> [AlgorithmStatementModel] {
            let projected = values.map { statement in
                statement.replacingCurrentProcess(with: .variable("self"))
            }.map { statement in
                localRoots.reduce(statement) { projectedStatement, root in
                    projectedStatement.replacingProcessLocalFamily(named: root, with: .variable(root))
                }
            }.map { statement in
                statement.mappingExpressions(lowerAnonymousLambdas)
            }
            return projected
        }

        func step(_ value: AlgorithmStepModel) -> AlgorithmStepModel {
            .init(
                label: value.label,
                statements: statements(value.statements),
                loopCondition: value.loopCondition.map(expression)
            )
        }

        func component(_ value: AlgorithmComponentModel) -> AlgorithmComponentModel {
            switch value {
            case .shared(let declaration): return .shared(state(declaration))
            case .process(let process):
                return .process(
                    .init(
                        typeName: process.typeName,
                        domain: expression(process.domain),
                        fairness: process.fairness,
                        components: process.components.map(component)
                    )
                )
            case .procedure(let procedure):
                return .procedure(
                    .init(
                        name: procedure.name,
                        parameters: procedure.parameters.map {
                            .init(root: $0.root, initial: expression($0.initial), swiftTypeName: $0.swiftTypeName)
                        },
                        components: procedure.components.map(component)
                    )
                )
            case .invariant(let invariant):
                return .invariant(.init(name: invariant.name, body: expression(invariant.body)))
            case .temporal(let declaration):
                return .temporal(.init(name: declaration.name, expr: declaration.expr.map(expression)))
            case .invalidPlacement:
                return value
            case .formalOperator(let definition):
                return .formalOperator(
                    .init(
                        name: definition.name,
                        parameters: definition.parameters,
                        body: expression(definition.body),
                        plusCalPhase: definition.plusCalPhase,
                        plusCalDependencies: definition.plusCalDependencies
                    )
                )
            case .stateConstraint(let constraint): return .stateConstraint(expression(constraint))
            case .local(let declaration): return .local(state(declaration))
            case .step(let declaration): return .step(step(declaration))
            }
        }

        return .init(
            name: name,
            sequentialFairness: sequentialFairness,
            components: components.map(component)
        )
    }
}

internal struct AuthoredPlusCalAlgorithmPlan: Sendable {
    let name: String
    let sequentialFairness: SequentialAlgorithmFairness
    let shared: [AlgorithmStateModel]
    let procedures: [AlgorithmProcedureModel]
    let processes: [AuthoredPlusCalProcessPlan]
    let sequentialSteps: [AlgorithmStepModel]

    init(_ source: AlgorithmModel) {
        let algorithm = source.plusCalProjection()
        var used = algorithm.authoredIdentifiers
        let processNames = algorithm.processes.indices.map { index in
            let stem = "pcalProcess\(index + 1)"
            var candidate = stem
            var suffix = 2
            while used.contains(candidate) {
                candidate = "\(stem)_\(suffix)"
                suffix += 1
            }
            used.insert(candidate)
            return candidate
        }

        name = algorithm.name
        sequentialFairness = algorithm.sequentialFairness
        shared = algorithm.components.compactMap {
            guard case .shared(let declaration) = $0 else { return nil }
            return declaration
        }
        procedures = algorithm.procedures
        processes = zip(algorithm.processes, processNames).enumerated().map { index, value in
            .init(
                process: value.0,
                name: value.1,
                owner: .process(
                    algorithm: algorithm.name,
                    ordinal: index,
                    typeName: value.0.typeName
                )
            )
        }
        sequentialSteps = algorithm.sequentialSteps
    }

    var processNames: [String] {
        processes.map(\.name)
    }
}

internal struct AuthoredPlusCalProcessPlan: Sendable {
    let name: String
    let owner: ControlOwner
    let swiftType: String
    let domain: StateExpr
    let fairness: AlgorithmFairness
    let locals: [AlgorithmStateModel]
    let steps: [AlgorithmStepModel]

    init(process: AlgorithmProcessModel, name: String, owner: ControlOwner) {
        self.name = name
        self.owner = owner
        swiftType = process.typeName
        domain = process.domain
        fairness = process.fairness
        locals = process.components.compactMap {
            guard case .local(let declaration) = $0 else { return nil }
            return declaration
        }
        steps = process.steps
    }
}

internal struct CompiledAuthoredPlusCalAlgorithmPlan: Sendable {
    let name: String
    let sequentialFairness: SequentialAlgorithmFairness
    let shared: [CompiledAuthoredPlusCalState]
    let procedures: [CompiledAuthoredPlusCalProcedure]
    let processes: [CompiledAuthoredPlusCalProcess]
    let sequentialSteps: [CompiledAuthoredPlusCalStep]
    let properties: [CompiledPropertyLayout]
    let translatorOwnedPropertyNames: Set<String>
}

internal struct CompiledAuthoredPlusCalState: Sendable {
    enum Initialization: Sendable {
        case expression(CompiledExpression)
        case memberOf(CompiledExpression)
    }

    let variable: VariableID
    let initialization: Initialization
}

internal struct CompiledAuthoredPlusCalProcedure: Sendable {
    let id: ProcedureID
    let parameters: [BinderID]
    let parameterVariables: [VariableID]
    let locals: [CompiledAuthoredPlusCalState]
    let steps: [CompiledAuthoredPlusCalStep]
}

internal struct CompiledAuthoredPlusCalProcess: Sendable {
    let name: String
    let binder: BinderID
    let swiftType: String
    let domain: CompiledExpression
    let fairness: AlgorithmFairness
    let locals: [CompiledAuthoredPlusCalState]
    let steps: [CompiledAuthoredPlusCalStep]
}

internal struct CompiledAuthoredPlusCalStep: Sendable {
    let label: ControlLocationID
    let statements: [CompiledAuthoredPlusCalStatement]
    let loopCondition: CompiledExpression?
}

internal struct CompiledAuthoredPlusCalAssignment: Sendable {
    let target: CompiledAuthoredPlusCalLValue
    let value: CompiledExpression
}

internal enum CompiledAuthoredPlusCalLValue: Sendable {
    case root(VariableID)
    case function(root: VariableID, key: CompiledExpression)
}

internal indirect enum CompiledAuthoredPlusCalStatement: Sendable {
    case when(CompiledExpression)
    case assert(CompiledExpression)
    case set(target: CompiledAuthoredPlusCalLValue, value: CompiledExpression)
    case parallel([CompiledAuthoredPlusCalAssignment])
    case letBinding(variable: BinderID, value: CompiledExpression, [CompiledAuthoredPlusCalStatement])
    case with(variable: BinderID, source: CompiledExpression, [CompiledAuthoredPlusCalStatement])
    case ifElse(CompiledExpression, [CompiledAuthoredPlusCalStatement], [CompiledAuthoredPlusCalStatement])
    case either([CompiledAuthoredPlusCalStatement], [CompiledAuthoredPlusCalStatement])
    case goto(ControlLocationID)
    case call(target: ProcedureID, arguments: [CompiledExpression])
    case `return`
    case skip
}

package indirect enum AlgorithmComponentModel: Sendable {
    case shared(AlgorithmStateModel)
    case process(AlgorithmProcessModel)
    case procedure(AlgorithmProcedureModel)
    case invariant(NamedStatePredicate)
    case temporal(NamedTemporal)
    case formalOperator(FormalOperatorDefinition)
    /// A TLC state-space bound whose excluded states are omitted from exploration.
    case stateConstraint(StateExpr)
    case invalidPlacement(InvalidAlgorithmComponent)
    case local(AlgorithmStateModel)
    case step(AlgorithmStepModel)
}

package enum InvalidAlgorithmComponent: String, Sendable {
    case genericFairness
    case assumption

    package var expectedPlacement: String {
        switch self {
        case .genericFairness:
            "Algorithm(..., fairness:) for sequential fairness or Each(..., fairness:) for process fairness"
        case .assumption:
            "an assumption declared in the formal specification"
        }
    }

    package var actualPlacement: String {
        switch self {
        case .genericFairness: "generic fairness declaration inside Algorithm"
        case .assumption: "Assume declaration inside Algorithm"
        }
    }

    package var nextSafeAction: String {
        switch self {
        case .genericFairness: "Move the fairness requirement to Algorithm or Each."
        case .assumption: "Move the assumption outside Algorithm."
        }
    }
}

/// One formal PlusCal procedure.
package struct AlgorithmProcedureModel: Sendable {
    package let name: String
    package let parameters: [AlgorithmProcedureParameterModel]
    package let components: [AlgorithmComponentModel]

    package var locals: [AlgorithmStateModel] {
        components.compactMap {
            guard case .local(let state) = $0 else { return nil }
            return state
        }
    }

    package var steps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }

    package init(
        name: String,
        parameters: [AlgorithmProcedureParameterModel],
        components: [AlgorithmComponentModel]
    ) {
        self.name = name
        self.parameters = parameters
        self.components = components
    }
}

package struct AlgorithmProcedureParameterModel: Sendable {
    package let root: String
    package let initial: StateExpr
    package let swiftTypeName: String?

    package init(root: String, initial: StateExpr, swiftTypeName: String?) {
        self.root = root
        self.initial = initial
        self.swiftTypeName = swiftTypeName
    }
}

package struct AlgorithmProcessModel: Sendable {
    package let typeName: String
    package let domain: StateExpr
    package let fairness: AlgorithmFairness
    package let components: [AlgorithmComponentModel]

    package var steps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }

    package init(typeName: String, domain: StateExpr, fairness: AlgorithmFairness, components: [AlgorithmComponentModel]) {
        self.typeName = typeName
        self.domain = domain
        self.fairness = fairness
        self.components = components
    }
}

package enum AlgorithmFairness: Sendable {
    case none
    case weak
    case strong
}

package struct AlgorithmStateModel: Sendable {
    package let root: String
    package let initialization: VariableInitialization
    package let swiftTypeName: String?

    package init(
        root: String,
        initialization: VariableInitialization,
        swiftTypeName: String? = nil
    ) {
        self.root = root
        self.initialization = initialization.normalized
        self.swiftTypeName = swiftTypeName
    }
}

package struct AlgorithmStepModel: Sendable {
    package let label: AlgorithmLabelModel
    package let statements: [AlgorithmStatementModel]
    /// A labeled PlusCal `while` loop. A true condition returns to `label`; a
    /// false condition advances to the following step.
    package let loopCondition: StateExpr?

    package init(label: AlgorithmLabelModel, statements: [AlgorithmStatementModel], loopCondition: StateExpr? = nil) {
        self.label = label
        self.statements = statements
        self.loopCondition = loopCondition
    }
}

package struct AlgorithmLabelModel: Sendable, Hashable {
    package let name: String

    package init(name: String) {
        self.name = name
    }
}

package enum AlgorithmLValueModel: Sendable, Equatable {
    case root(String)
    case function(root: String, key: StateExpr)

    package var root: String {
        switch self {
        case .root(let root), .function(let root, _):
            return root
        }
    }
}

package struct AlgorithmAssignmentModel: Sendable, Equatable {
    package let target: AlgorithmLValueModel
    package let value: StateExpr

    package init(target: AlgorithmLValueModel, value: StateExpr) {
        self.target = target
        self.value = value
    }
}

package indirect enum AlgorithmStatementModel: Sendable, Equatable {
    case rejected(AlgorithmDiagnosticCode)
    case when(StateExpr)
    case assert(StateExpr)
    case set(target: AlgorithmLValueModel, value: StateExpr)
    case parallel([AlgorithmAssignmentModel])
    case letBinding(variable: String, value: StateExpr, [AlgorithmStatementModel])
    case with(variable: String, source: StateExpr, [AlgorithmStatementModel])
    case ifElse(StateExpr, [AlgorithmStatementModel], [AlgorithmStatementModel])
    case either([AlgorithmStatementModel], [AlgorithmStatementModel])
    case choose(variable: String, domain: [TLAValue], [AlgorithmStatementModel])
    case goto(AlgorithmLabelModel)
    case call(target: String, arguments: [StateExpr])
    case `return`
    case stop
    case skip
}
