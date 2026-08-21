struct CompiledRecordExpression: Sendable {
    struct Field: Sendable {
        let id: FieldID
        let value: CompiledStateExpr
    }

    let fields: [Field]

    init(_ fields: [Field]) {
        self.fields = fields.sorted { $0.id.ordinal < $1.id.ordinal }
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
    case recordAccess(CompiledStateExpr, FieldID)
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
}

struct CompiledActionBinding: Sendable {
    let binder: BinderID
    let values: [TLAValue]
}

struct CompiledInvariant: Sendable {
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
    let name: String
    let expression: CompiledTemporalExpr
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

struct CompiledSymmetrySet: Sendable {
    let values: Set<TLAValue>
}

struct CompiledSymmetricCollection: Sendable {
    let members: [TLAValue]
}

struct CompiledModel: Sendable {
    let initialValues: [VariableID: CompiledValue]
    let variableInitializers: [VariableID: CompiledVariableInitializer]
    let actions: [CompiledAction]
    let invariants: [CompiledInvariant]
    let temporalProperties: [CompiledTemporal]
    let constraint: CompiledStateExpr?
    let assume: CompiledStateExpr?
    let formalOperatorDefinitions: [CompiledFormalOperatorDefinition]
    let recursiveFunctions: [CompiledRecursiveFunction]
    let symmetrySets: [CompiledSymmetrySet]
    let symmetricCollections: [CompiledSymmetricCollection]
}
