import Foundation

/// Operation metadata only. Operands are owned by the resolved expression.
package enum ResolvedOperation: Hashable, Sendable {
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

    /// Strict operand order is shared by formal evaluation and native generation.
    package var evaluatesRightOperandFirst: Bool {
        switch self {
        case .divide, .integerDivide, .modulo, .in, .functionApply: true
        default: false
        }
    }
}

/// The finished occurrence owns its types; operand types belong to its children.
package struct ResolvedExpression: Hashable, Sendable {
    // Copies retain occurrence identity without recursively owned class instances.
    private let identity = UUID()
    package let operation: ResolvedOperation
    package let resultType: CompiledValueType
    package let children: [Self]

    package init(operation: ResolvedOperation, resultType: CompiledValueType,
         children: [Self]) {
        self.operation = operation
        self.resultType = resultType
        self.children = children
    }

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


/// Resolved call identities over the checked compiler program.
/// Function identities distinguish specializations of the same formal body.
package struct ResolvedFunctionID: Hashable, Sendable {
    package let ordinal: Int
    package init(ordinal: Int) { self.ordinal = ordinal }
}
package struct ResolvedCallbackID: Hashable, Sendable {
    package let ordinal: Int
    package init(ordinal: Int) { self.ordinal = ordinal }
}

package enum ResolvedCallTarget: Hashable, Sendable {
    case function(ResolvedFunctionID)
    case callback(ResolvedCallbackID)
}

package struct ResolvedCallbackArgument: Hashable, Sendable {
    package let parameter: ResolvedCallbackID
    package let target: ResolvedCallTarget
}

package struct ResolvedCall: Hashable, Sendable {
    package let target: ResolvedCallTarget
    package let callbacks: [ResolvedCallbackArgument]
}

package struct ResolvedCallback: Sendable {
    package let parameters: [CompiledValueType]
    package let result: CompiledValueType
}

package struct ResolvedFunction: Sendable {
    package let parameters: [(binder: BinderID, type: CompiledValueType)]
    package let resultType: CompiledValueType
    package let callbacks: [ResolvedCallbackID]
    package let body: ResolvedExpression
    package let domainGuard: ResolvedExpression?
}

package struct ResolvedProjectionPair: Hashable, Sendable {
    package let source: CompiledValueType
    package let target: CompiledValueType
}

package struct ResolvedProgram: Sendable {
    package let identity: CompilationIdentity
    package let layout: CompiledLayout
    package let behavior: CompiledBehavior<ResolvedExpression>
    package let enums: CompiledEnums
    /// Implicit conversions required by this program, including their components.
    package let projections: Set<ResolvedProjectionPair>
    package func canProject(source: CompiledValueType, to target: CompiledValueType) -> Bool {
        source == target || projections.contains(.init(source: source, target: target))
    }

    package let variableTypes: [VariableID: CompiledValueType]
    package let bindingTypes: [BinderID: CompiledValueType]
    package let functions: [ResolvedFunction]
    package let callbacks: [ResolvedCallback]
    package subscript(_ id: ResolvedFunctionID) -> ResolvedFunction { functions[id.ordinal] }
    package subscript(_ id: ResolvedCallbackID) -> ResolvedCallback { callbacks[id.ordinal] }
    package subscript(_ id: ActionID) -> CompiledAction<ResolvedExpression> { behavior.actions[id.ordinal] }
}
