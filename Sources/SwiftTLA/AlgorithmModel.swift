package struct DirectCopySource: Codable, Equatable, Sendable {
    package struct Copy: Codable, Equatable, Sendable {
        package let target: String
        package let read: String
    }

    package struct Row: Codable, Equatable, Sendable {
        package let label: String
        package let copies: [Copy]
    }

    package let algorithm: String
    package let fields: Set<String>
    package let rows: [Row]

    private enum CodingKeys: String, CodingKey {
        case algorithm, fields, rows
    }

    package func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(algorithm, forKey: .algorithm)
        try values.encode(fields.sorted(), forKey: .fields)
        try values.encode(rows, forKey: .rows)
    }
}

package struct AlgorithmModel: Sendable {
    package let name: String
    package let displayLabel: String?
    package let sequentialFairness: SequentialAlgorithmFairness
    package let components: [AlgorithmComponentModel]

    package init(
        name: String,
        displayLabel: String? = nil,
        sequentialFairness: SequentialAlgorithmFairness = .none,
        components: [AlgorithmComponentModel]
    ) {
        self.name = name
        self.displayLabel = displayLabel
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
                    if let name = process.name { names.insert(name) }
                    collect(process.components, into: &names)
                case .procedure(let procedure):
                    names.insert(procedure.name)
                    procedure.parameters.forEach { names.insert($0.root) }
                    procedure.locals.forEach { names.insert($0.root) }
                    procedure.steps.forEach {
                        names.insert($0.label.name)
                        names.formUnion($0.statements.algorithmScopeNames)
                    }
                case .invariant(let invariant), .reachable(let invariant):
                    names.insert(invariant.name)
                case .temporal(let temporal):
                    names.insert(temporal.name)
                case .formalOperator(let definition):
                    names.insert(definition.name)
                case .stateConstraint, .actionConstraint, .invalidPlacement:
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
        resolvingAtomicSteps(retainingScalarCopyRoutes: false).model
    }

    func resolvingAtomicSteps(
        retainingScalarCopyRoutes: Bool, retainingSequentialAssignmentTargets: Bool = false
    ) -> (model: AlgorithmModel, scalarCopies: [String: StraightLineAssignmentCheck.ScalarCopyReceipt],
          assignmentTargets: [String: [String: String]]) {
        var usedBindings = authoredIdentifiers
        var nextBinding = 0
        let scalarRoots = orderedIntCopyRoots
        var scalarCopies: [String: StraightLineAssignmentCheck.ScalarCopyReceipt] = [:]
        var assignmentTargets: [String: [String: String]] = [:]

        func binding() -> String {
            while true {
                let candidate = "__atomic_\(nextBinding)"
                nextBinding += 1
                if usedBindings.insert(candidate).inserted {
                    return candidate
                }
            }
        }

        func component(_ value: AlgorithmComponentModel) -> AlgorithmComponentModel {
            switch value {
            case .step(let step):
                let record: ((String, String) -> Void)? = retainingSequentialAssignmentTargets && scalarRoots != nil
                    ? { name, target in assignmentTargets[step.label.name, default: [:]][name] = target }
                    : nil
                if let scalarRoots, let plan = scheduleDirectScalarCopies(step.statements, roots: scalarRoots,
                    binding: binding, recordAssignment: record) {
                    if retainingScalarCopyRoutes { scalarCopies[step.label.name] = plan.receipt }
                    return .step(.init(label: step.label, statements: plan.statements, loopCondition: step.loopCondition))
                }
                var displacedTargets: [String: String] = [:]
                let controlledLoop = processes.isEmpty && procedures.isEmpty
                    && step.loopCondition != nil && step.loopCondition != .value(.bool(true))
                    && step.loopCondition != .value(.bool(false))
                let recordScheduled = record.map { record in
                    { (name: String, assignment: ScheduledAtomicAssignment) in record(name, assignment.target) }
                }
                let statements = scheduleAtomicStatements(step.statements, binding: binding, recordAssignment: recordScheduled,
                    retainingDisabledTargets: controlledLoop) {
                    displacedTargets[$0] = $1
                }
                return .step(.init(label: step.label, statements: statements, loopCondition: step.loopCondition,
                    displacedAssignmentTargets: displacedTargets))
            case .process(let process):
                return .process(.init(typeName: process.typeName, name: process.name, population: process.population,
                    fairness: process.fairness, components: process.components.map(component),
                    resolvedElementType: process.resolvedElementType,
                    fairnessExcludedLabels: process.fairnessExcludedLabels))
            case .procedure(let procedure):
                return .procedure(.init(name: procedure.name, parameters: procedure.parameters,
                    components: procedure.components.map(component)))
            default:
                return value
            }
        }
        let resolved = AlgorithmModel(name: name, sequentialFairness: sequentialFairness,
            components: components.map(component))
        return (resolved, scalarCopies, assignmentTargets)
    }

    package var directScalarCopyInput: DirectCopySource? {
        let steps = sequentialSteps
        guard let roots = orderedIntCopyRoots, !steps.isEmpty,
              components.count == roots.count + steps.count else { return nil }
        var rows: [DirectCopySource.Row] = []
        for step in steps {
            guard let copies = directScalarCopyOperands(step.statements, roots: roots) else { return nil }
            rows.append(.init(label: step.label.name, copies: copies))
        }
        return DirectCopySource(algorithm: name, fields: roots, rows: rows)
    }

    private var orderedIntCopyRoots: Set<String>? {
        guard processes.isEmpty, procedures.isEmpty, sequentialSteps.allSatisfy({ $0.loopCondition == nil }) else { return nil }
        var roots: Set<String> = []
        for component in components {
            guard case .shared(let state) = component else { continue }
            guard state.swiftTypeName == "Int",
                  state.resolvedValueType == nil || state.resolvedValueType == .int,
                  roots.insert(state.root).inserted else { return nil }
        }
        return roots.isEmpty ? nil : roots
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
                tlaName: value.tlaName, displayLabel: value.displayLabel,
                swiftTypeName: value.swiftTypeName,
                resolvedValueType: value.resolvedValueType
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
                        name: process.name,
                        population: process.population.map(expression),
                        fairness: process.fairness,
                        components: process.components.map(component),
                        resolvedElementType: process.resolvedElementType,
                        fairnessExcludedLabels: process.fairnessExcludedLabels
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
                return .invariant(.init(name: invariant.name, body: expression(invariant.body), reference: invariant.reference))
            case .reachable(let predicate):
                return .reachable(.init(name: predicate.name, body: expression(predicate.body), reference: predicate.reference))
            case .temporal(let declaration):
                return .temporal(.init(name: declaration.name, expr: declaration.expr.map(expression),
                    bindings: declaration.bindings, reference: declaration.reference))
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
            case .stateConstraint(let constraint): return .stateConstraint(.init(
                expression(constraint.expression), sourceOffset: constraint.sourceOffset))
            case .actionConstraint(let constraint): return .actionConstraint(.init(
                expression(constraint.expression), sourceOffset: constraint.sourceOffset))
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

/// The structural source witness emitted by `#spec` for straight-line Int algorithms.
public enum _OrderedIntSourceComponent: Sendable {
    case variable(root: String, initialization: VariableInitialization)
    case step(label: String, assignments: [(root: String, value: StateExpr)])
}

extension AlgorithmModel {
    package func matchesOrderedIntSource(_ expected: [_OrderedIntSourceComponent]) -> Bool {
        guard components.count == expected.count else { return false }
        for (source, actual) in zip(expected, components) {
            switch (source, actual) {
            case (.variable(let root, let initialization), .shared(let state)):
                guard state.root == root, state.initialization == initialization else { return false }
                if case .value = initialization {
                    guard state.swiftTypeName == "Int" else { return false }
                } else {
                    guard state.swiftTypeName == nil || state.swiftTypeName == "Int" else { return false }
                }
            case (.step(let label, let assignments), .step(let step)):
                guard step.label.name == label, step.loopCondition == nil,
                      step.statements.count == assignments.count else { return false }
                for (source, actual) in zip(assignments, step.statements) {
                    guard case .set(.root(let root), let value) = actual,
                          root == source.root, value == source.value else { return false }
                }
            default: return false
            }
        }
        return true
    }
}

internal struct AuthoredPlusCalAlgorithmPlan: Sendable {
    let name: String
    let renderedName: String
    let sequentialFairness: SequentialAlgorithmFairness
    let shared: [AlgorithmStateModel]
    let procedures: [AlgorithmProcedureModel]
    let processes: [AuthoredPlusCalProcessPlan]
    let sequentialSteps: [AlgorithmStepModel]

    init(_ source: AlgorithmModel) {
        let algorithm = source.plusCalProjection()
        var used = algorithm.authoredIdentifiers
        var renderedName = algorithm.name
        while isPlusCalDeclarationName(renderedName) == false {
            renderedName = "_\(renderedName)"
        }
        renderedName = StateExpr.freshBoundName(renderedName, avoiding: used)
        used.insert(renderedName)
        let processNames = algorithm.processes.indices.map { index in
            if let name = algorithm.processes[index].name { return name }
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
        self.renderedName = renderedName
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
    let fixedID: StateExpr?
    let domain: StateExpr
    let fairness: AlgorithmFairness
    let fairnessExcludedLabels: [AlgorithmLabelModel]
    let locals: [AlgorithmStateModel]
    let steps: [AlgorithmStepModel]

    init(process: AlgorithmProcessModel, name: String, owner: ControlOwner) {
        self.name = name
        self.owner = owner
        swiftType = process.typeName
        fixedID = process.population.fixedID
        domain = process.domain
        fairness = process.fairness
        fairnessExcludedLabels = process.fairnessExcludedLabels
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
    let fixedID: CompiledExpression?
    let domain: CompiledExpression
    let fairness: AlgorithmFairness
    let fairnessExcludedSteps: Set<ControlLocationID>
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

internal indirect enum CompiledAuthoredPlusCalLValue: Sendable {
    case root(VariableID)
    case function(base: CompiledAuthoredPlusCalLValue, key: CompiledExpression)
    case field(CompiledAuthoredPlusCalLValue, String)

    var expression: CompiledExpression {
        switch self {
        case .root(let root): .stateVariable(root)
        case .function(let base, let key): .init(operation: .functionApply, children: [base.expression, key])
        case .field(let base, let name): .recordAccess(base.expression, name)
        }
    }

    func resolvingRead(_ expression: CompiledExpression) -> Self {
        switch self {
        case .root: self
        case .function(let base, _): .function(base: base.resolvingRead(expression.children[0]), key: expression.children[1])
        case .field(let base, let name): .field(base.resolvingRead(expression.children[0]), name)
        }
    }
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
    case reachable(NamedStatePredicate)
    case temporal(NamedTemporal)
    case formalOperator(FormalOperatorDefinition)
    /// A TLC state-space bound whose excluded states are omitted from exploration.
    case stateConstraint(ModelPredicateClause)
    case actionConstraint(ModelPredicateClause)
    case invalidPlacement(InvalidAlgorithmComponent)
    case local(AlgorithmStateModel)
    case step(AlgorithmStepModel)
}

package enum InvalidAlgorithmComponent: String, Sendable {
    case genericFairness
    case assumption
    case parameterizedStep
    case unknownStateField

    package var expectedPlacement: String {
        switch self {
        case .unknownStateField: "a whole generated State field"
        case .genericFairness:
            "Algorithm(..., fairness:) for sequential fairness or Each(..., fairness:) for process fairness"
        case .assumption:
            "an assumption declared in the formal specification"
        case .parameterizedStep:
            "a parameterized Do declared directly in the formal specification"
        }
    }

    package var actualPlacement: String {
        switch self {
        case .unknownStateField: "unregistered state key path"
        case .genericFairness: "generic fairness declaration inside Algorithm"
        case .assumption: "Assume declaration inside Algorithm"
        case .parameterizedStep: "parameterized Do inside Algorithm"
        }
    }

    package var nextSafeAction: String {
        switch self {
        case .unknownStateField: "Use a direct key path to a generated state field."
        case .genericFairness: "Move the fairness requirement to Algorithm or Each."
        case .assumption: "Move the assumption outside Algorithm."
        case .parameterizedStep: "Declare independent actions outside Algorithm, or use Each for processes and With for local choices."
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

package enum AlgorithmProcessPopulation: Sendable {
    case family(StateExpr)
    case fixed(StateExpr)

    var domain: StateExpr {
        switch self {
        case .family(let set): set
        case .fixed(let id): .setLiteral([id])
        }
    }

    var fixedID: StateExpr? {
        guard case .fixed(let id) = self else { return nil }
        return id
    }

    func map(_ transform: (StateExpr) -> StateExpr) -> Self {
        switch self {
        case .family(let set): .family(transform(set))
        case .fixed(let id): .fixed(transform(id))
        }
    }
}

package struct AlgorithmProcessModel: Sendable {
    package let typeName: String
    package let name: String?
    package let resolvedElementType: CompiledValueType?
    package let population: AlgorithmProcessPopulation
    package var domain: StateExpr { population.domain }
    package let fairness: AlgorithmFairness
    package let fairnessExcludedLabels: [AlgorithmLabelModel]
    package let components: [AlgorithmComponentModel]

    package var steps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }

    package init(typeName: String, name: String? = nil, population: AlgorithmProcessPopulation, fairness: AlgorithmFairness,
        components: [AlgorithmComponentModel], resolvedElementType: CompiledValueType? = nil,
        fairnessExcludedLabels: [AlgorithmLabelModel] = []) {
        self.typeName = typeName
        self.name = name
        self.resolvedElementType = resolvedElementType
        self.population = population
        self.fairness = fairness
        self.fairnessExcludedLabels = fairnessExcludedLabels
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
    package let tlaName: String?
    package let displayLabel: String?
    package let swiftTypeName: String?
    package let resolvedValueType: CompiledValueType?
    package let exposed: Bool

    package init(
        root: String,
        initialization: VariableInitialization,
        tlaName: String? = nil, displayLabel: String? = nil,
        swiftTypeName: String? = nil,
        resolvedValueType: CompiledValueType? = nil,
        exposed: Bool = false
    ) {
        self.root = root
        self.initialization = initialization.normalized
        self.tlaName = tlaName
        self.displayLabel = displayLabel
        self.swiftTypeName = swiftTypeName
        self.resolvedValueType = resolvedValueType
        self.exposed = exposed
    }
}

package struct AlgorithmStepModel: Sendable {
    package let label: AlgorithmLabelModel
    package let statements: [AlgorithmStatementModel]
    /// A labeled PlusCal `while` loop. A true condition returns to `label`; a
    /// false condition advances to the following step.
    package let loopCondition: StateExpr?
    let displacedAssignmentTargets: [String: String]

    package init(label: AlgorithmLabelModel, statements: [AlgorithmStatementModel], loopCondition: StateExpr? = nil) {
        self.init(label: label, statements: statements, loopCondition: loopCondition, displacedAssignmentTargets: [:])
    }

    init(label: AlgorithmLabelModel, statements: [AlgorithmStatementModel], loopCondition: StateExpr?,
         displacedAssignmentTargets: [String: String]) {
        self.label = label
        self.statements = statements
        self.loopCondition = loopCondition
        self.displacedAssignmentTargets = displacedAssignmentTargets
    }
}

package struct AlgorithmLabelModel: Sendable, Hashable {
    package let name: String

    package init(name: String) {
        self.name = name
    }
}

package indirect enum AlgorithmLValueModel: Sendable, Equatable {
    case root(String)
    case function(base: AlgorithmLValueModel, key: StateExpr)
    case field(AlgorithmLValueModel, String)

    package var root: String {
        switch self {
        case .root(let root): return root
        case .function(let base, _), .field(let base, _): return base.root
        }
    }

    package var expression: StateExpr {
        switch self {
        case .root(let root): .variable(root)
        case .function(let base, let key): .functionApply(base.expression, key)
        case .field(let base, let name): .recordAccess(base.expression, name)
        }
    }

    func assigning(_ value: StateExpr) -> StateExpr {
        switch self {
        case .root: value
        case .function(let base, let key): base.assigning(.except(base.expression, key, value))
        case .field(let base, let name): base.assigning(.except(base.expression, .value(.string(name)), value))
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
    package static func guardedChoice(
        _ first: [Self], _ second: [Self], remaining: [[Self]]
    ) -> Self {
        var branches = [first, second] + remaining
        let right = branches.removeLast()
        var choice = Self.either(branches.removeLast(), right)
        for branch in branches.reversed() {
            choice = .either(branch, [choice])
        }
        return choice
    }

    package static func copyField(target: String, source: String) -> Self {
        .set(target: .root(target), value: .variable(source))
    }

    case rejected(AlgorithmDiagnosticCode)
    case when(StateExpr)
    case assert(StateExpr)
    case set(target: AlgorithmLValueModel, value: StateExpr)
    case parallel([AlgorithmAssignmentModel])
    case letBinding(variable: String, value: StateExpr, [AlgorithmStatementModel])
    case with(variable: String, source: StateExpr, [AlgorithmStatementModel])
    case ifElse(StateExpr, [AlgorithmStatementModel], [AlgorithmStatementModel])
    case either([AlgorithmStatementModel], [AlgorithmStatementModel])
    case choose(variable: String, domain: StateExpr, [AlgorithmStatementModel])
    case goto(AlgorithmLabelModel)
    case call(target: String, arguments: [StateExpr])
    case `return`
    case stop
    case skip
}

private func directScalarCopyOperands(
    _ statements: [AlgorithmStatementModel], roots: Set<String>
) -> [DirectCopySource.Copy]? {
    guard !statements.isEmpty else { return nil }
    var copies: [DirectCopySource.Copy] = []
    for statement in statements {
        guard case .set(.root(let target), .variable(let read)) = statement,
              roots.contains(target), roots.contains(read) else { return nil }
        copies.append(.init(target: target, read: read))
    }
    return copies
}

private func scheduleDirectScalarCopies(
    _ statements: [AlgorithmStatementModel], roots: Set<String>, binding: () -> String,
    recordAssignment: ((String, String) -> Void)?
) -> (statements: [AlgorithmStatementModel], receipt: StraightLineAssignmentCheck.ScalarCopyReceipt)? {
    typealias Reference = StraightLineAssignmentCheck.ScalarCopyReceipt.Reference
    guard let copies = directScalarCopyOperands(statements, roots: roots) else { return nil }

    var writes = Dictionary(uniqueKeysWithValues: roots.map { ($0, Reference.state($0)) })
    var reads: [Reference] = []
    var binders: [String] = []
    for copy in copies {
        // The RHS uses the previous route even when it reads its own target.
        reads.append(writes[copy.read, default: .state(copy.read)])
        let name = binding()
        binders.append(name)
        recordAssignment?(name, copy.target)
        writes[copy.target] = .capture(binders.count)
    }

    func expression(_ reference: Reference) -> StateExpr {
        switch reference {
        case .state(let root): .variable(root)
        case .capture(let position): .variable(binders[position - 1])
        }
    }

    let assignments = copies.enumerated().compactMap { offset, copy -> AlgorithmAssignmentModel? in
        let position = offset + 1
        guard writes[copy.target] == .capture(position) else { return nil }
        return .init(target: .root(copy.target), value: .variable(binders[offset]))
    }
    var body: [AlgorithmStatementModel] = [.parallel(assignments)]
    for (name, read) in zip(binders, reads).reversed() {
        body = [.letBinding(variable: name, value: expression(read), body)]
    }
    return (body, .init(reads: reads, writes: writes))
}

package struct ScheduledAtomicBindingWrite: Sendable {
    package let predecessor: String?
    package let target: String
    package let binding: String
}

package struct ScheduledAtomicAssignment: Sendable {
    let update: ScheduledAtomicBindingWrite
    let incomingBindings: [String: StateExpr]

    var target: String { update.target }
}

func scheduleAtomicStatements(
    _ statements: [AlgorithmStatementModel], binding: () -> String,
    recordAssignment: ((String, ScheduledAtomicAssignment) -> Void)? = nil, retainingDisabledTargets: Bool = false,
    displace: (String, String) -> Void
) -> [AlgorithmStatementModel] {
    // Snapshot each write where it occurs, then publish one assignment per
    // root at the end of the atomic branch. PlusCal labels require that form.
    struct Replacements {
        var bindings: [String: StateExpr] = [:]
        var lastWrite: ScheduledAtomicBindingWrite?

        func recording(_ update: ScheduledAtomicBindingWrite) -> Self {
            var result = self
            result.bindings[update.target] = .variable(update.binding)
            result.lastWrite = update
            return result
        }
    }

    func schedule(
        _ values: [AlgorithmStatementModel],
        assignments: [AlgorithmAssignmentModel] = [],
        replacements: Replacements = .init()
    ) -> [AlgorithmStatementModel] {
        let finalWrites = assignments.isEmpty ? [] : [AlgorithmStatementModel.parallel(assignments)]
        guard let statement = values.first else { return finalWrites }
        let suffix = Array(values.dropFirst())
        func expression(_ value: StateExpr) -> StateExpr {
            StateExpr.substituteVariables(replacements.bindings, in: value)
        }
        func continued(_ body: [AlgorithmStatementModel]) -> [AlgorithmStatementModel] {
            schedule(body + suffix, assignments: assignments, replacements: replacements)
        }
        switch statement {
        case .set(let target, let value):
            let update = ScheduledAtomicBindingWrite(predecessor: replacements.lastWrite?.binding,
                target: target.root, binding: binding())
            let updated = expression(target.assigning(value))
            let next = replacements.recording(update)
            recordAssignment?(update.binding, .init(update: update, incomingBindings: replacements.bindings))
            if case .variable(let capture)? = replacements.bindings[update.target] {
                displace(capture, update.target)
            }
            let pending = assignments.filter { $0.target.root != update.target }
                + [.init(target: .root(update.target), value: .variable(update.binding))]
            return [.letBinding(variable: update.binding, value: updated,
                schedule(suffix, assignments: pending, replacements: next))]
        case .when(.value(.bool(false))) where retainingDisabledTargets:
            // The guard drops the pending writes, but checked captures before it can still fail.
            for assignment in assignments {
                if case .variable(let capture) = assignment.value { displace(capture, assignment.target.root) }
            }
            return [statement] + continued([])
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
                source: expression(domain), body)])
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
    return schedule(statements)
}
