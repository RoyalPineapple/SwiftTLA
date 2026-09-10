import SwiftTLA

/// Immutable expansion-time annotations over the existing compiled program.
/// Function identities distinguish specializations of the same formal body.
struct NativeFunctionID: Hashable, Sendable { let ordinal: Int }
struct NativeCallbackID: Hashable, Sendable { let ordinal: Int }

/// A shared expression may call different callbacks in different specializations.
struct NativeCallSite: Hashable, Sendable {
    let expression: NativeCheckedExpression
    let function: NativeFunctionID?
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
    let body: NativeCheckedExpression
    let domainGuard: NativeCheckedExpression?
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
    let expressions: [NativeCheckedExpression]
    let calls: [NativeCallSite: NativeResolvedCall]
    let functions: [NativeResolvedFunction]
    let callbacks: [NativeResolvedCallback]
    /// A value initializer is represented by its existing `.value` expression.
    let initializations: [VariableID: NativeCheckedExpression]
    let actions: [ActionID: CompiledActionExpr<NativeCheckedExpression>]
    let invariants: [PropertyID: NativeCheckedExpression]
    let constraint: NativeCheckedExpression?
    let assume: NativeCheckedExpression?

    subscript(_ id: NativeFunctionID) -> NativeResolvedFunction { functions[id.ordinal] }
    subscript(_ id: NativeCallbackID) -> NativeResolvedCallback { callbacks[id.ordinal] }
}
