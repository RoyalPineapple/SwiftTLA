internal struct AlgorithmModel: Sendable {
    let name: String
    let components: [AlgorithmComponentModel]

    var processes: [AlgorithmProcessModel] {
        components.compactMap {
            guard case .process(let process) = $0 else { return nil }
            return process
        }
    }
}

internal indirect enum AlgorithmComponentModel: Sendable {
    case shared(AlgorithmStateModel)
    case process(AlgorithmProcessModel)
    case local(AlgorithmStateModel)
    case step(AlgorithmStepModel)
    case propertyBoundary
}

internal struct AlgorithmProcessModel: Sendable {
    let typeName: String
    let domain: [TLAValue]
    let components: [AlgorithmComponentModel]

    var steps: [AlgorithmStepModel] {
        components.compactMap {
            guard case .step(let step) = $0 else { return nil }
            return step
        }
    }
}

internal struct AlgorithmStateModel: Sendable {
    let root: String
    let initial: TLAValue
}

internal struct AlgorithmStepModel: Sendable {
    let label: AlgorithmLabelModel
    let statements: [AlgorithmStatementModel]
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
    case set(target: AlgorithmLValueModel, value: StateExpr)
    case ifElse(StateExpr, [AlgorithmStatementModel], [AlgorithmStatementModel])
    case either([AlgorithmStatementModel], [AlgorithmStatementModel])
    case choose(variable: String, domain: [TLAValue], [AlgorithmStatementModel])
    case goto(AlgorithmLabelModel)
    case stop
}
