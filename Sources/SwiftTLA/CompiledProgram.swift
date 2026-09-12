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

package struct ResolvedCall: Hashable, Sendable {
    package let target: ResolvedCallTarget
    package let callbacks: [ResolvedCallbackID: ResolvedCallTarget]
}

package struct ResolvedCallback: Sendable {
    package let parameters: [CompiledValueType]
    package let result: CompiledValueType
}

package struct ResolvedFunction: Sendable {
    package let parameters: [(binder: BinderID, type: CompiledValueType)]
    package let resultType: CompiledValueType
    package let callbacks: [ResolvedCallbackID]
    package let body: CompiledExpression
    package let domainGuard: CompiledExpression?
}

package struct ResolvedProjectionPair: Hashable, Sendable {
    package let source: CompiledValueType
    package let target: CompiledValueType
}

package struct CompiledProgram: Sendable {
    package let identity: CompilationIdentity
    package let layout: CompiledLayout
    package let behavior: CompiledBehavior
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
    package subscript(_ id: ActionID) -> CompiledAction { behavior.actions[id.ordinal] }
}
