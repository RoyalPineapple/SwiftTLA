struct CompiledRecordExpression: Sendable {
    struct Field: Sendable {
        let id: FieldID
        let key: CompiledValue
        let value: CompiledStateExpr
    }

    let fields: [Field]

    init(_ fields: [Field]) {
        self.fields = fields.sorted { $0.key.canonicalEncoding < $1.key.canonicalEncoding }
    }
}

indirect enum CompiledStateExpr: Sendable {
    case value(TLAValue)
    case stateVariable(VariableID)
    case boundValue(BinderID)
    case controlLocation(ControlLocationID)
    case operatorReference(OperatorID)

    case add(CompiledStateExpr, CompiledStateExpr)
    case subtract(CompiledStateExpr, CompiledStateExpr)
    case multiply(CompiledStateExpr, CompiledStateExpr)
    case divide(CompiledStateExpr, CompiledStateExpr)
    case modulo(CompiledStateExpr, CompiledStateExpr)
    case negate(CompiledStateExpr)
    case integerDivide(CompiledStateExpr, CompiledStateExpr)
    case equal(CompiledStateExpr, CompiledStateExpr)
    case notEqual(CompiledStateExpr, CompiledStateExpr)
    case lessThan(CompiledStateExpr, CompiledStateExpr)
    case lessOrEqual(CompiledStateExpr, CompiledStateExpr)
    case greaterThan(CompiledStateExpr, CompiledStateExpr)
    case greaterOrEqual(CompiledStateExpr, CompiledStateExpr)
    case and(CompiledStateExpr, CompiledStateExpr)
    case or(CompiledStateExpr, CompiledStateExpr)
    case not(CompiledStateExpr)
    case ifThenElse(CompiledStateExpr, CompiledStateExpr, CompiledStateExpr)

    case setLiteral([CompiledStateExpr])
    case `in`(CompiledStateExpr, CompiledStateExpr)
    case subset(CompiledStateExpr, CompiledStateExpr)
    case union(CompiledStateExpr, CompiledStateExpr)
    case intersection(CompiledStateExpr, CompiledStateExpr)
    case setDifference(CompiledStateExpr, CompiledStateExpr)
    case cardinality(CompiledStateExpr)
    case setFilter(CompiledStateExpr, BinderID, CompiledStateExpr)
    case setMap(CompiledStateExpr, BinderID, CompiledStateExpr)
    case powerSet(CompiledStateExpr)
    case unionAll(CompiledStateExpr)
    case integerRange(CompiledStateExpr, CompiledStateExpr)

    case tupleLiteral([CompiledStateExpr])
    case tupleAccess(CompiledStateExpr, Int)
    case tupleDynamicAccess(CompiledStateExpr, CompiledStateExpr)
    case tupleLength(CompiledStateExpr)
    case tupleAppend(CompiledStateExpr, CompiledStateExpr)
    case tupleHead(CompiledStateExpr)
    case tupleTail(CompiledStateExpr)
    case tupleConcatenate(CompiledStateExpr, CompiledStateExpr)

    case recordLiteral(CompiledRecordExpression)
    case recordAccess(CompiledStateExpr, FieldID, CompiledValue)
    case domain(CompiledStateExpr)
    case functionLiteral(CompiledStateExpr, BinderID, CompiledStateExpr)
    case functionApply(CompiledStateExpr, CompiledStateExpr)
    case except(CompiledStateExpr, CompiledStateExpr, CompiledStateExpr)
    case caseExpr([CompiledStateExpr], CompiledStateExpr?)

    case forAll(CompiledStateExpr, BinderID, CompiledStateExpr)
    case exists(CompiledStateExpr, BinderID, CompiledStateExpr)
    case choose(CompiledStateExpr, BinderID, CompiledStateExpr)
    case enabledAction(ActionID)
    case sequenceFromSet(CompiledStateExpr)
    case setSum(CompiledStateExpr, CompiledStateExpr)
    case functionSet(CompiledStateExpr, CompiledStateExpr)
    case foldFunction(CompiledFormalLambda, initial: CompiledStateExpr, sequence: CompiledStateExpr)
    case operatorApplication(CompiledFormalOperator, [CompiledFormalCallArgument])
    case recursiveCall(OperatorID, [CompiledStateExpr])
    case letValue(BinderID, CompiledStateExpr, CompiledStateExpr)
    case letIn([CompiledLocalOperator], CompiledStateExpr)
}

extension CompiledStateExpr {
    var isStateIndependent: Bool {
        switch self {
        case .value, .controlLocation, .operatorReference:
            return true
        case .stateVariable, .boundValue, .enabledAction:
            return false
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
             .divide(let lhs, let rhs), .modulo(let lhs, let rhs), .integerDivide(let lhs, let rhs),
             .equal(let lhs, let rhs), .notEqual(let lhs, let rhs), .lessThan(let lhs, let rhs),
             .lessOrEqual(let lhs, let rhs), .greaterThan(let lhs, let rhs), .greaterOrEqual(let lhs, let rhs),
             .and(let lhs, let rhs), .or(let lhs, let rhs), .in(let lhs, let rhs), .subset(let lhs, let rhs),
             .union(let lhs, let rhs), .intersection(let lhs, let rhs), .setDifference(let lhs, let rhs),
             .tupleDynamicAccess(let lhs, let rhs), .tupleAppend(let lhs, let rhs),
             .tupleConcatenate(let lhs, let rhs), .functionApply(let lhs, let rhs),
             .except(let lhs, let rhs, _), .setSum(let lhs, let rhs), .functionSet(let lhs, let rhs):
            return lhs.isStateIndependent && rhs.isStateIndependent
        case .negate(let value), .not(let value), .cardinality(let value), .powerSet(let value),
             .unionAll(let value), .tupleAccess(let value, _), .tupleLength(let value),
             .tupleHead(let value), .tupleTail(let value), .domain(let value), .sequenceFromSet(let value):
            return value.isStateIndependent
        case .recordAccess(let value, _, _):
            return value.isStateIndependent
        case .ifThenElse(let condition, let then, let otherwise):
            return condition.isStateIndependent && then.isStateIndependent && otherwise.isStateIndependent
        case .setLiteral(let values), .tupleLiteral(let values):
            return values.allSatisfy(\.isStateIndependent)
        case .setFilter, .setMap, .integerRange, .recordLiteral, .functionLiteral, .caseExpr,
             .forAll, .exists, .choose, .foldFunction, .operatorApplication, .recursiveCall,
             .letValue, .letIn:
            return false
        }
    }
}

struct CompiledFormalLambda: Sendable {
    let parameters: [BinderID]
    let body: CompiledStateExpr
}

enum CompiledFormalOperator: Sendable {
    case lambda(CompiledFormalLambda)
    case reference(OperatorID, arity: Int)

    var arity: Int {
        switch self {
        case .lambda(let lambda): return lambda.parameters.count
        case .reference(_, let arity): return arity
        }
    }
}

indirect enum CompiledFormalCallArgument: Sendable {
    case value(CompiledStateExpr)
    case `operator`(CompiledFormalOperator)
}

struct CompiledLocalOperator: Sendable {
    let id: OperatorID
    let parameters: [BinderID]
    let domain: CompiledStateExpr?
    let body: CompiledStateExpr
    let isRecursive: Bool
}

indirect enum CompiledActionExpr: Sendable {
    case assign(VariableID, CompiledStateExpr)
    case unchanged(VariableID)
    case guard_(CompiledStateExpr)
    case chooseAction(VariableID, CompiledStateExpr)
    case existsAction(BinderID, CompiledStateExpr, CompiledActionExpr)
    case ifElse(CompiledStateExpr, CompiledActionExpr, CompiledActionExpr)
    case define(BinderID, CompiledStateExpr, CompiledActionExpr)
    case and(CompiledActionExpr, CompiledActionExpr)
    case or(CompiledActionExpr, CompiledActionExpr)
}

struct CompiledAction: Sendable {
    let id: ActionID
    let bindings: [CompiledActionBinding]
    let body: CompiledActionExpr
    let symmetricCollection: VariableID?
}

struct CompiledActionBinding: Sendable {
    let binder: BinderID
    let sourceName: String
    let values: [TLAValue]
    let generatedSwiftType: String?
}

struct CompiledInvariant: Sendable {
    let id: PropertyID
    let name: String
    let body: CompiledStateExpr
}

indirect enum CompiledTemporalExpr: Sendable {
    case always(CompiledStateExpr)
    case eventually(CompiledStateExpr)
    case alwaysEventually(CompiledStateExpr)
    case eventuallyAlways(CompiledStateExpr)
    case leadsTo(CompiledStateExpr, CompiledStateExpr)
}

struct CompiledTemporal: Sendable {
    let id: PropertyID
    let name: String
    let expression: CompiledTemporalExpr
}

enum CompiledTheoremBody: Sendable {
    case temporal(CompiledTemporalExpr)
    case state(CompiledStateExpr)
}

struct CompiledTheorem: Sendable {
    let name: String
    let body: CompiledTheoremBody
}

struct CompiledActionCall: Hashable, Sendable {
    let action: ActionID
    let arguments: [TLAValue]
}

struct CompiledFairnessCondition: Sendable {
    enum Scope: Hashable, Sendable {
        case next
        case action(ActionID)
        case actionCall(CompiledActionCall)
    }

    let scope: Scope
    let isStrong: Bool
}

struct CompiledFormalOperatorDefinition: Sendable {
    let id: OperatorID
    let parameters: [CompiledFormalParameter]
    let body: CompiledStateExpr
}

enum CompiledFormalParameter: Sendable {
    case value(BinderID)
    case `operator`(OperatorID, arity: Int)
}

struct CompiledRecursiveFunction: Sendable {
    let id: OperatorID
    let parameters: [BinderID]
    let body: CompiledStateExpr
}

struct CompiledVariableInitializer: Sendable {
    let initialSet: CompiledStateExpr?
    let initExpr: CompiledStateExpr?
    let lazySet: CompiledStateExpr?
}

struct CompiledFormalModuleReplacement: Sendable {
    let moduleName: String
    let operatorName: String
    let definitionName: String
    let expression: CompiledStateExpr
}

struct CompiledSymmetrySet: Sendable {
    let values: Set<TLAValue>
}

struct CompiledSymmetricCollection: Sendable {
    let variable: VariableID
    let members: [TLAValue]
    let domainSymbol: String
    let initial: CompiledValue
}

struct CompiledSemantics: Sendable {
    let checkDeadlock: Bool
    let initialValues: [VariableID: CompiledValue]
    let variableInitializers: [VariableID: CompiledVariableInitializer]
    let actions: [CompiledAction]
    let invariants: [CompiledInvariant]
    let temporalProperties: [CompiledTemporal]
    let theorems: [CompiledTheorem]
    let fairness: [CompiledFairnessCondition]
    let constraint: CompiledStateExpr?
    let assume: CompiledStateExpr?
    let formalOperatorDefinitions: [CompiledFormalOperatorDefinition]
    let recursiveFunctions: [CompiledRecursiveFunction]
    let formalModuleReplacements: [CompiledFormalModuleReplacement]
    let symmetrySets: [CompiledSymmetrySet]
    let symmetricCollections: [CompiledSymmetricCollection]
}
