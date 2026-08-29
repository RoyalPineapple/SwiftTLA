internal struct AlgorithmModel: Sendable {
    let name: String
    let sequentialFairness: SequentialAlgorithmFairness
    let components: [AlgorithmComponentModel]

    init(
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

        var result: Set<String> = ["self"]
        collect(components, into: &result)
        return result
    }

    func plusCalProjection() -> AlgorithmModel {
        let localRoots: Set<String> = Set(processes.flatMap { process in
            process.components.compactMap { component in
                guard case .local(let declaration) = component else { return nil }
                return declaration.root
            }
        })
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

        func lowerAnonymousLambdas(_ value: StateExpr) -> StateExpr {
            StateExpr.renamingRecursiveCalls(
                in: value,
                using: { $0 },
                lowerAnonymousLambdaApplications: true
            )
        }

        func expression(_ value: StateExpr) -> StateExpr {
            let family = localRoots.reduce(value) { result, root in
                result.replacingProcessLocalFamily(named: root, with: .variable(root))
            }
            return lowerAnonymousLambdas(family.replacingCurrentProcess(with: .variable("self")))
        }

        func temporal(_ value: TemporalExpr) -> TemporalExpr {
            switch value {
            case .always(let predicate): return .always(expression(predicate))
            case .eventually(let predicate): return .eventually(expression(predicate))
            case .alwaysEventually(let predicate): return .alwaysEventually(expression(predicate))
            case .eventuallyAlways(let predicate): return .eventuallyAlways(expression(predicate))
            case .leadsTo(let source, let destination): return .leadsTo(expression(source), expression(destination))
            }
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
                swiftTypeName: value.swiftTypeName,
                isTuple: value.isTuple
            )
        }

        func statements(_ values: [AlgorithmStatementModel]) -> [AlgorithmStatementModel] {
            let projected = values.map { statement in
                statement.replacingCurrentProcess(with: .variable("self"))
            }.map { statement in
                localRoots.reduce(statement) { result, root in
                    result.replacingProcessLocalFamily(named: root, with: .variable(root))
                }
            }.map { statement in
                statement.mappingExpressions(lowerAnonymousLambdas)
            }
            return schedule(projected)
        }

        func call(
            _ target: String,
            arguments: [StateExpr],
            after assignments: [AlgorithmAssignmentModel],
            followedBy suffix: [AlgorithmStatementModel]
        ) -> [AlgorithmStatementModel] {
            let assignmentGroup = assignments.isEmpty ? [] : [AlgorithmStatementModel.parallel(assignments)]
            guard arguments.isEmpty == false, assignments.isEmpty == false else {
                return assignmentGroup + [.call(target: target, arguments: arguments)] + suffix
            }
            let bindings = arguments.map { argument in (name: binding(), value: argument) }
            let call = AlgorithmStatementModel.call(
                target: target,
                arguments: bindings.map { .variable($0.name) }
            )
            return bindings.reversed().reduce(assignmentGroup + [call] + suffix) { body, value in
                [.letBinding(variable: value.name, value: value.value, body)]
            }
        }

        func movingScope(
            _ variable: String,
            body: [AlgorithmStatementModel],
            over suffix: [AlgorithmStatementModel]
        ) -> (String, [AlgorithmStatementModel]) {
            guard suffix.algorithmScopeNames.contains(variable) else { return (variable, body) }
            let fresh = StateExpr.freshBoundName(
                variable,
                avoiding: usedBindings
                    .union(body.algorithmScopeNames)
                    .union(suffix.algorithmScopeNames)
            )
            usedBindings.insert(fresh)
            return (
                fresh,
                body.map {
                    $0.substitutingVariable(
                        variable,
                        with: .variable(fresh),
                        assignmentTargets: .replaceWhenVariable
                    )
                }
            )
        }

        func assignmentStatements(_ assignments: [AlgorithmAssignmentModel]) -> [AlgorithmStatementModel] {
            assignments.map { .set(target: $0.target, value: $0.value) }
        }

        func schedule(_ values: [AlgorithmStatementModel]) -> [AlgorithmStatementModel] {
            var reads: [AlgorithmStatementModel] = []
            var assignments: [AlgorithmAssignmentModel] = []
            var terminals: [AlgorithmStatementModel] = []

            for (index, statement) in values.enumerated() {
                let suffix = Array(values.dropFirst(index + 1))
                switch statement {
                case .set(let target, let value):
                    assignments.append(.init(target: target, value: value))
                case .parallel(let values):
                    assignments.append(contentsOf: values)
                case .await, .assert, .skip, .rejected:
                    reads.append(statement)
                case .goto, .return:
                    terminals.append(statement)
                case .stop:
                    terminals.append(.goto(.init(name: CompilerControlSymbol.done.rawValue)))
                case .call(let target, let arguments):
                    return reads + call(
                        target,
                        arguments: arguments,
                        after: assignments,
                        followedBy: suffix
                    ) + terminals
                case .letBinding(let variable, let value, let body):
                    let scoped = movingScope(variable, body: body, over: suffix)
                    return reads + [
                        .letBinding(
                            variable: scoped.0,
                            value: value,
                            schedule(assignmentStatements(assignments) + scoped.1 + suffix + terminals)
                        )
                    ]
                case .with(let variable, let source, let body):
                    let scoped = movingScope(variable, body: body, over: suffix)
                    return reads + [
                        .with(
                            variable: scoped.0,
                            source: source,
                            schedule(assignmentStatements(assignments) + scoped.1 + suffix + terminals)
                        )
                    ]
                case .choose(let variable, let domain, let body):
                    let scoped = movingScope(variable, body: body, over: suffix)
                    return reads + [
                        .with(
                            variable: scoped.0,
                            source: .setLiteral(domain.map(StateExpr.value)),
                            schedule(assignmentStatements(assignments) + scoped.1 + suffix + terminals)
                        )
                    ]
                case .ifElse(let condition, let then, let otherwise):
                    return reads + [
                        .ifElse(
                            condition,
                            schedule(assignmentStatements(assignments) + then + suffix + terminals),
                            schedule(assignmentStatements(assignments) + otherwise + suffix + terminals)
                        )
                    ]
                case .either(let first, let second):
                    return reads + [
                        .either(
                            schedule(assignmentStatements(assignments) + first + suffix + terminals),
                            schedule(assignmentStatements(assignments) + second + suffix + terminals)
                        )
                    ]
                }
            }
            let assignmentGroup = assignments.isEmpty ? [] : [AlgorithmStatementModel.parallel(assignments)]
            return reads + assignmentGroup + terminals
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
                        domain: process.domain,
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
                return .temporal(.init(name: declaration.name, expr: temporal(declaration.expr)))
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
    let domain: [TLAValue]
    let fairness: AlgorithmFairness
    let locals: [AlgorithmStateModel]
    let steps: [AlgorithmStepModel]

    init(process: AlgorithmProcessModel, name: String, owner: ControlOwner) {
        self.name = name
        self.owner = owner
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
    let properties: [CompiledAuthoredPlusCalProperty]
    let translatorOwnedPropertyNames: Set<String>
}

internal enum CompiledAuthoredPlusCalProperty: Sendable {
    case invariant(id: PropertyID, name: String)
    case temporal(id: PropertyID, name: String)

    var id: PropertyID {
        switch self {
        case .invariant(let id, _), .temporal(let id, _): id
        }
    }

    var name: String {
        switch self {
        case .invariant(_, let name), .temporal(_, let name): name
        }
    }
}

internal struct CompiledAuthoredPlusCalState: Sendable {
    enum Initialization: Sendable {
        case expression(CompiledStateExpr)
        case memberOf(CompiledStateExpr)
    }

    let variable: VariableID
    let initialization: Initialization
}

internal struct CompiledAuthoredPlusCalProcedure: Sendable {
    let id: ProcedureID
    let parameters: [BinderID]
    let locals: [CompiledAuthoredPlusCalState]
    let steps: [CompiledAuthoredPlusCalStep]
}

internal struct CompiledAuthoredPlusCalProcess: Sendable {
    let name: String
    let domain: [CompiledValue]
    let fairness: AlgorithmFairness
    let locals: [CompiledAuthoredPlusCalState]
    let steps: [CompiledAuthoredPlusCalStep]
}

internal struct CompiledAuthoredPlusCalStep: Sendable {
    let label: ControlLocationID
    let statements: [CompiledAuthoredPlusCalStatement]
    let loopCondition: CompiledStateExpr?
}

internal struct CompiledAuthoredPlusCalAssignment: Sendable {
    let target: CompiledAuthoredPlusCalLValue
    let value: CompiledStateExpr
}

internal enum CompiledAuthoredPlusCalLValue: Sendable {
    case root(VariableID)
    case function(root: VariableID, key: CompiledStateExpr)
}

internal indirect enum CompiledAuthoredPlusCalStatement: Sendable {
    case await(CompiledStateExpr)
    case assert(CompiledStateExpr)
    case set(target: CompiledAuthoredPlusCalLValue, value: CompiledStateExpr)
    case parallel([CompiledAuthoredPlusCalAssignment])
    case letBinding(variable: BinderID, value: CompiledStateExpr, [CompiledAuthoredPlusCalStatement])
    case with(variable: BinderID, source: CompiledStateExpr, [CompiledAuthoredPlusCalStatement])
    case ifElse(CompiledStateExpr, [CompiledAuthoredPlusCalStatement], [CompiledAuthoredPlusCalStatement])
    case either([CompiledAuthoredPlusCalStatement], [CompiledAuthoredPlusCalStatement])
    case goto(ControlLocationID)
    case call(target: ProcedureID, arguments: [CompiledStateExpr])
    case `return`
    case skip
}

internal indirect enum AlgorithmComponentModel: Sendable {
    case shared(AlgorithmStateModel)
    case process(AlgorithmProcessModel)
    case procedure(AlgorithmProcedureModel)
    case invariant(NamedInvariant)
    case temporal(NamedTemporal)
    case formalOperator(FormalOperatorDefinition)
    /// A TLC state-space bound whose excluded states are omitted from exploration.
    case stateConstraint(StateExpr)
    case invalidPlacement(InvalidAlgorithmComponent)
    case local(AlgorithmStateModel)
    case step(AlgorithmStepModel)
}

internal enum InvalidAlgorithmComponent: String, Sendable {
    case genericFairness
    case assumption

    var expectedPlacement: String {
        switch self {
        case .genericFairness:
            "Algorithm(..., fairness:) for sequential fairness or Each(..., fairness:) for process fairness"
        case .assumption:
            "an assumption declared in the formal specification"
        }
    }

    var actualPlacement: String {
        switch self {
        case .genericFairness: "generic fairness declaration inside Algorithm"
        case .assumption: "Assume declaration inside Algorithm"
        }
    }

    var nextSafeAction: String {
        switch self {
        case .genericFairness: "Move the fairness requirement to Algorithm or Each."
        case .assumption: "Move the assumption outside Algorithm."
        }
    }
}

/// One formal PlusCal procedure.
internal struct AlgorithmProcedureModel: Sendable {
    let name: String
    let parameters: [AlgorithmProcedureParameterModel]
    let components: [AlgorithmComponentModel]

    var locals: [AlgorithmStateModel] {
        components.compactMap {
            guard case .local(let state) = $0 else { return nil }
            return state
        }
    }

    var steps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }

    init(
        name: String,
        parameters: [AlgorithmProcedureParameterModel],
        components: [AlgorithmComponentModel]
    ) {
        self.name = name
        self.parameters = parameters
        self.components = components
    }
}

internal struct AlgorithmProcedureParameterModel: Sendable {
    let root: String
    let initial: StateExpr
    let swiftTypeName: String?
}

internal struct AlgorithmProcessModel: Sendable {
    let typeName: String
    let domain: [TLAValue]
    let fairness: AlgorithmFairness
    let components: [AlgorithmComponentModel]

    var steps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }
}

internal enum AlgorithmFairness: Sendable {
    case none
    case weak
    case strong
}

internal struct AlgorithmStateModel: Sendable {
    let root: String
    let initialization: VariableInitialization
    let swiftTypeName: String?
    let isTuple: Bool

    init(
        root: String,
        initialization: VariableInitialization,
        swiftTypeName: String? = nil,
        isTuple: Bool = false
    ) {
        self.root = root
        self.initialization = initialization.normalized
        self.swiftTypeName = swiftTypeName
        self.isTuple = isTuple
    }
}

internal struct AlgorithmStepModel: Sendable {
    let label: AlgorithmLabelModel
    let statements: [AlgorithmStatementModel]
    /// A labeled PlusCal `while` loop. A true condition returns to `label`; a
    /// false condition advances to the following step.
    let loopCondition: StateExpr?

    init(label: AlgorithmLabelModel, statements: [AlgorithmStatementModel], loopCondition: StateExpr? = nil) {
        self.label = label
        self.statements = statements
        self.loopCondition = loopCondition
    }
}

internal struct AlgorithmLabelModel: Sendable, Hashable {
    let name: String
}

internal enum AlgorithmLValueModel: Sendable, Equatable {
    case root(String)
    case function(root: String, key: StateExpr)

    var root: String {
        switch self {
        case .root(let root), .function(let root, _):
            return root
        }
    }
}

internal struct AlgorithmAssignmentModel: Sendable, Equatable {
    let target: AlgorithmLValueModel
    let value: StateExpr
}

internal indirect enum AlgorithmStatementModel: Sendable, Equatable {
    case rejected(AlgorithmDiagnosticCode)
    case await(StateExpr)
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
