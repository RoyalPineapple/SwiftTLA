import SwiftTLA

/// Immutable expansion-time annotations over the existing compiled program.
/// Expression IDs identify uses, so one formal body can have several Swift shapes.
struct NativeExpressionID: Hashable, Sendable { let ordinal: Int }
struct NativeFunctionID: Hashable, Sendable { let ordinal: Int }
struct NativeCallbackID: Hashable, Sendable { let ordinal: Int }

struct NativeResolvedExpression: Sendable {
    let expression: CompiledStateExpr
    let resultType: NativeType
    let computationType: NativeType
    /// Children follow structural IR order, independent of evaluation scheduling.
    let children: [NativeExpressionID]
    let call: NativeResolvedCall?
}

enum NativeResolvedCallTarget: Sendable {
    case function(NativeFunctionID)
    case callback(NativeCallbackID)
}

struct NativeResolvedCallbackArgument: Sendable {
    let parameter: NativeCallbackID
    let target: NativeResolvedCallTarget
}

struct NativeResolvedCall: Sendable {
    let target: NativeResolvedCallTarget
    let callbacks: [NativeResolvedCallbackArgument]
}

struct NativeResolvedCallback: Sendable {
    let parameters: [NativeType]
    let result: NativeType
}

struct NativeResolvedFunction: Sendable {
    let parameters: [BinderID]
    let parameterTypes: [NativeType]
    let resultType: NativeType
    let callbacks: [NativeCallbackID]
    let body: NativeExpressionID
    let domainGuard: NativeExpressionID?
}

struct NativeProjectionPair: Hashable, Sendable {
    let source: NativeType
    let target: NativeType
}

struct NativeResolvedProgram: Sendable {
    /// Implicit conversions required by this program, including their components.
    let projections: Set<NativeProjectionPair>
    func canProject(source: NativeType, to target: NativeType) -> Bool {
        source == target || projections.contains(.init(source: source, target: target))
    }

    let variableTypes: [VariableID: NativeType]
    let bindingTypes: [BinderID: NativeType]
    let expressions: [NativeResolvedExpression]
    let functions: [NativeResolvedFunction]
    let callbacks: [NativeResolvedCallback]
    /// A value initializer is represented by its existing `.value` expression.
    let initializations: [VariableID: NativeExpressionID]
    let actions: [ActionID: CompiledActionExpr<NativeExpressionID>]
    let invariants: [PropertyID: NativeExpressionID]
    let constraint: NativeExpressionID?
    let assume: NativeExpressionID?

    subscript(_ id: NativeExpressionID) -> NativeResolvedExpression { expressions[id.ordinal] }
    subscript(_ id: NativeFunctionID) -> NativeResolvedFunction { functions[id.ordinal] }
    subscript(_ id: NativeCallbackID) -> NativeResolvedCallback { callbacks[id.ordinal] }
}
