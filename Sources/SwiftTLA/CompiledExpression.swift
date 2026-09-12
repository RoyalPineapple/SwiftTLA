import Foundation

/// The operation and binding metadata for a compiled expression.
package enum CompiledOperation: Hashable, Sendable {
    case value(CompiledValue)
    case stateVariable(VariableID)
    case boundValue(BinderID)
    case controlLocation(ControlLocationID)
    case operatorReference(OperatorID)
    case add
    case subtract
    case multiply
    case divide
    case modulo
    case negate
    case assertView(FormalValueShape)
    case convert
    case integerDivide
    case equal
    case notEqual
    case lessThan
    case lessOrEqual
    case greaterThan
    case greaterOrEqual
    case and
    case or
    case not
    case ifThenElse
    case setLiteral
    case `in`
    case subset
    case union
    case intersection
    case setDifference
    case cardinality
    case setFilter(BinderID)
    case setMap(BinderID)
    case powerSet
    case unionAll
    case integerRange
    case tupleLiteral
    case tupleAccess(Int)
    case tupleDynamicAccess
    case tupleLength
    case tupleAppend
    case tupleHead
    case tupleTail
    case tupleConcatenate
    case tupleRemoving
    case sequenceSelect(BinderID)
    case recordLiteral([CompiledRecordField])
    case recordAccess(CompiledRecordField)
    case domain
    case functionLiteral(BinderID)
    case functionApply
    case except
    case caseExpr(hasOtherwise: Bool)
    case forAll(BinderID)
    case exists(BinderID)
    case choose(BinderID)
    case enabledAction(ActionID)
    case sequenceFromSet
    case setSum
    case functionSet
    case foldFunction([BinderID])
    case letValue(BinderID)
    case call(ResolvedCall)
    case checkedCall(CheckedOperatorCall, origin: OperatorID?, operatorParameters: Set<OperatorID>)
    case operatorApplication(CompiledFormalOperator, [CompiledFormalCallArgument])
    case letIn([OperatorID])

    package var diagnosticName: String {
        Mirror(reflecting: self).children.first?.label ?? String(describing: self)
    }

    /// Strict operand order is shared by formal evaluation and native generation.
    package var evaluatesRightOperandFirst: Bool {
        switch self {
        case .divide, .integerDivide, .modulo, .in, .functionApply: true
        default: false
        }
    }
}

/// One expression representation from lowering through checking and backend execution.
/// Checking fills the result type and records explicit conversions.
package struct CompiledExpression: Hashable, Sendable {
    // Copies retain occurrence identity without recursively owned class instances.
    private let identity = UUID()
    package let operation: CompiledOperation
    package let resultType: CompiledValueType
    package let children: [Self]

    package init(operation: CompiledOperation, resultType: CompiledValueType = .unknown,
         children: [Self]) {
        self.operation = operation
        self.resultType = resultType
        self.children = children
    }

    /// The operation before its explicit representation conversion.
    package var computation: Self {
        if case .convert = operation { return children[0] }
        return self
    }

    package var computationType: CompiledValueType { computation.resultType }

    /// Recognizes Boolean constants without evaluating state reads or fallible operations.
    package var booleanConstant: Bool? {
        var expression = self
        var inverted = false
        while case .not = expression.operation {
            expression = expression.children[0]
            inverted.toggle()
        }
        guard case .value(.boolean(let value)) = expression.operation else { return nil }
        return inverted ? !value : value
    }

    package static func == (lhs: Self, rhs: Self) -> Bool { lhs.identity == rhs.identity }
    package func hash(into hasher: inout Hasher) { hasher.combine(identity) }
}

extension CompiledExpression {
    package var referencedOperator: OperatorID? {
        guard case .operatorReference(let id) = operation else { return nil }
        return id
    }

    package static func value(_ value: CompiledValue) -> Self {
        .init(operation: .value(value), children: [])
    }
    package static func stateVariable(_ id: VariableID) -> Self {
        .init(operation: .stateVariable(id), children: [])
    }
    package static func boundValue(_ id: BinderID) -> Self {
        .init(operation: .boundValue(id), children: [])
    }
    package static func controlLocation(_ id: ControlLocationID) -> Self {
        .init(operation: .controlLocation(id), children: [])
    }
    package static func operatorReference(_ id: OperatorID) -> Self {
        .init(operation: .operatorReference(id), children: [])
    }
    package static func assertView(_ value: Self, _ shape: FormalValueShape) -> Self {
        .init(operation: .assertView(shape), children: [value])
    }
    package static func ifThenElse(_ condition: Self, _ then: Self, _ otherwise: Self) -> Self {
        .init(operation: .ifThenElse, children: [condition, then, otherwise])
    }
    package static func setLiteral(_ members: [Self]) -> Self {
        .init(operation: .setLiteral, children: members)
    }
    package static func setFilter(_ domain: Self, _ binder: BinderID, _ predicate: Self) -> Self {
        .init(operation: .setFilter(binder), children: [domain, predicate])
    }
    package static func setMap(_ value: Self, _ binder: BinderID, _ domain: Self) -> Self {
        .init(operation: .setMap(binder), children: [value, domain])
    }
    package static func integerRange(_ lowerBound: Self, _ upperBound: Self) -> Self {
        .init(operation: .integerRange, children: [lowerBound, upperBound])
    }
    package static func tupleLiteral(_ elements: [Self]) -> Self {
        .init(operation: .tupleLiteral, children: elements)
    }
    package static func tupleAccess(_ tuple: Self, _ index: Int) -> Self {
        .init(operation: .tupleAccess(index), children: [tuple])
    }
    package static func sequenceSelect(_ sequence: Self, _ binder: BinderID, _ predicate: Self) -> Self {
        .init(operation: .sequenceSelect(binder), children: [sequence, predicate])
    }
    package static func recordLiteral(_ fields: [CompiledRecordEntry]) -> Self {
        .init(operation: .recordLiteral(fields.map(\.declaration)), children: fields.map(\.value))
    }
    package static func recordAccess(_ record: Self, _ field: CompiledRecordField) -> Self {
        .init(operation: .recordAccess(field), children: [record])
    }
    package static func functionLiteral(_ domain: Self, _ binder: BinderID, _ value: Self) -> Self {
        .init(operation: .functionLiteral(binder), children: [domain, value])
    }
    package static func except(_ function: Self, _ key: Self, _ value: Self) -> Self {
        .init(operation: .except, children: [function, key, value])
    }
    package static func caseExpr(_ first: CompiledCaseBranch, _ remaining: [CompiledCaseBranch], otherwise: Self?) -> Self {
        let branches = ([first] + remaining).flatMap { [$0.condition, $0.value] }
        let children = branches + (otherwise.map { [$0] } ?? [])
        return .init(operation: .caseExpr(hasOtherwise: otherwise != nil), children: children)
    }
    package static func forAll(_ domain: Self, _ binder: BinderID, _ predicate: Self) -> Self {
        .init(operation: .forAll(binder), children: [domain, predicate])
    }
    package static func exists(_ domain: Self, _ binder: BinderID, _ predicate: Self) -> Self {
        .init(operation: .exists(binder), children: [domain, predicate])
    }
    package static func choose(_ domain: Self, _ binder: BinderID, _ predicate: Self) -> Self {
        .init(operation: .choose(binder), children: [domain, predicate])
    }
    package static func enabledAction(_ id: ActionID) -> Self {
        .init(operation: .enabledAction(id), children: [])
    }
    package static func foldFunction(parameters: [BinderID], body: Self, initial: Self, sequence: Self) -> Self {
        .init(operation: .foldFunction(parameters), children: [body, initial, sequence])
    }
    package static func operatorApplication(_ operation: CompiledFormalOperator, _ arguments: [CompiledFormalCallArgument]) -> Self {
        .init(operation: .operatorApplication(operation, arguments), children: [])
    }
    package static func letValue(_ binder: BinderID, _ value: Self, _ body: Self) -> Self {
        .init(operation: .letValue(binder), children: [value, body])
    }
    package static func letIn(_ declarations: [OperatorID], _ body: Self) -> Self {
        .init(operation: .letIn(declarations), children: [body])
    }
}
