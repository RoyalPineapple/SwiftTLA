internal struct AlgorithmModel: Sendable {
    let name: String
    let components: [AlgorithmComponentModel]

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
}

internal indirect enum AlgorithmComponentModel: Sendable {
    case shared(AlgorithmStateModel)
    case process(AlgorithmProcessModel)
    case invariant(NamedInvariant)
    case temporal(NamedTemporal)
    case fairness(FairnessCondition)
    case local(AlgorithmStateModel)
    case step(AlgorithmStepModel)
    case propertyBoundary
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
    let initial: StateExpr
    let initialSet: StateExpr?
    let swiftTypeName: String?

    init(
        root: String,
        initial: StateExpr,
        initialSet: StateExpr? = nil,
        swiftTypeName: String? = nil
    ) {
        self.root = root
        self.initial = initial
        self.initialSet = initialSet
        self.swiftTypeName = swiftTypeName
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

internal enum AlgorithmLValueModel: Sendable {
    case root(String)
    case function(root: String, key: StateExpr)

    var root: String {
        switch self {
        case .root(let root), .function(let root, _):
            return root
        }
    }
}

internal indirect enum AlgorithmStatementModel: Sendable {
    case await(StateExpr)
    case assert(StateExpr)
    case set(target: AlgorithmLValueModel, value: StateExpr)
    case with(variable: String, source: StateExpr, [AlgorithmStatementModel])
    case ifElse(StateExpr, [AlgorithmStatementModel], [AlgorithmStatementModel])
    case either([AlgorithmStatementModel], [AlgorithmStatementModel])
    case choose(variable: String, domain: [TLAValue], [AlgorithmStatementModel])
    case goto(AlgorithmLabelModel)
    case stop
    case skip
}
