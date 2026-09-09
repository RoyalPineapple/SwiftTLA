/// Immutable expansion-time annotations over the existing compiled program.
/// Expression IDs identify uses, so one formal body can have several Swift shapes.
package struct NativeExpressionID: Hashable, Sendable { package let ordinal: Int }
package struct NativeFunctionID: Hashable, Sendable { package let ordinal: Int }
package struct NativeCallbackID: Hashable, Sendable { package let ordinal: Int }

package struct NativeResolvedExpression: Sendable {
    package let expression: CompiledStateExpr
    package let resultType: NativeType
    package let computationType: NativeType
    /// Children follow structural IR order, independent of evaluation scheduling.
    package let children: [NativeExpressionID]
    package let call: NativeResolvedCall?
}

package enum NativeResolvedCallTarget: Sendable {
    case function(NativeFunctionID)
    case callback(NativeCallbackID)
}

package struct NativeResolvedCallbackArgument: Sendable {
    package let parameter: NativeCallbackID
    package let target: NativeResolvedCallTarget
}

package struct NativeResolvedCall: Sendable {
    package let target: NativeResolvedCallTarget
    package let callbacks: [NativeResolvedCallbackArgument]
}

package struct NativeResolvedCallback: Sendable {
    package let parameters: [NativeType]
    package let result: NativeType
}

package struct NativeResolvedFunction: Sendable {
    package let parameters: [BinderID]
    package let parameterTypes: [NativeType]
    package let resultType: NativeType
    package let callbacks: [NativeCallbackID]
    package let body: NativeExpressionID
    package let domainGuard: NativeExpressionID?
}

package struct NativeProjectionPair: Hashable, Sendable {
    package let source: NativeType
    package let target: NativeType
}

package struct NativeResolvedProgram: Sendable {
    /// Implicit conversions required by this program, including their components.
    package let projections: Set<NativeProjectionPair>
    package func canProject(source: NativeType, to target: NativeType) -> Bool {
        source == target || projections.contains(.init(source: source, target: target))
    }

    package let variableTypes: [VariableID: NativeType]
    package let bindingTypes: [BinderID: NativeType]
    package let expressions: [NativeResolvedExpression]
    package let functions: [NativeResolvedFunction]
    package let callbacks: [NativeResolvedCallback]
    /// A value initializer is represented by its existing `.value` expression.
    package let initializations: [VariableID: NativeExpressionID]
    package let actions: [ActionID: CompiledActionExpr<NativeExpressionID>]
    package let invariants: [PropertyID: NativeExpressionID]
    package let constraint: NativeExpressionID?
    package let assume: NativeExpressionID?

    package subscript(_ id: NativeExpressionID) -> NativeResolvedExpression { expressions[id.ordinal] }
    package subscript(_ id: NativeFunctionID) -> NativeResolvedFunction { functions[id.ordinal] }
    package subscript(_ id: NativeCallbackID) -> NativeResolvedCallback { callbacks[id.ordinal] }
}
