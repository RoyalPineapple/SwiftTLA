/// Resolved call identities over the checked compiler program.
/// Function identities distinguish specializations of the same formal body.
package struct ResolvedFunctionID: Hashable, Sendable {
    package let ordinal: Int
    package init(ordinal: Int) { self.ordinal = ordinal }
}
package struct ResolvedFunction: Sendable {
    package let parameters: [(binder: BinderID, type: CompiledValueType)]
    package let resultType: CompiledValueType
    package let body: CompiledExpression
    package let domainGuard: CompiledExpression?
}

package struct ResolvedProjectionPair: Hashable, Sendable {
    package let source: CompiledValueType
    package let target: CompiledValueType
}

package struct CompiledProgram: Sendable {
    package let identity: CompilationIdentity
    let moduleMetadata: CompiledModuleMetadata
    let requiredStandardModules: Set<StandardModule>
    package var moduleName: String { moduleMetadata.name }
    package let layout: CompiledLayout
    package let behavior: CompiledBehavior
    package let refinements: [CompiledRefinementProgram]
    package let enums: CompiledEnums
    /// Implicit conversions required by this program, including their components.
    package let projections: Set<ResolvedProjectionPair>
    package func canProject(source: CompiledValueType, to target: CompiledValueType) -> Bool {
        source == target || projections.contains(.init(source: source, target: target))
    }

    package let variableTypes: [VariableID: CompiledValueType]
    package let bindingTypes: [BinderID: CompiledValueType]
    package let binderNames: [BinderID: String]
    package let functions: [ResolvedFunction]
    let authoredAlgorithm: CompiledAuthoredPlusCalAlgorithmPlan?
    package subscript(_ id: ResolvedFunctionID) -> ResolvedFunction { functions[id.ordinal] }
    package subscript(_ id: ActionID) -> CompiledAction { behavior.actions[id.ordinal] }

    package func requireImmutableDomain(_ domain: CompiledExpression, path: String) throws {
        var pending = [domain]
        var visited: Set<CompiledExpression> = []
        var visitedFunctions: Set<ResolvedFunctionID> = []
        while let expression = pending.popLast() {
            guard visited.insert(expression).inserted else { continue }
            switch expression.operation {
            case .stateVariable, .enabledAction, .controlLocation:
                throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
                    path: path, expected: "an immutable domain independent of machine state",
                    actual: expression.operation.diagnosticName,
                    nextSafeAction: "Define the legal domain using values or model parameters, not state or enabled actions.")
            case .call(let id) where visitedFunctions.insert(id).inserted:
                pending.append(self[id].body)
                if let guardExpression = self[id].domainGuard { pending.append(guardExpression) }
            default: break
            }
            pending.append(contentsOf: expression.children)
        }
    }
}

/// An abstract native program and its state mapping, checked in the concrete program's scope.
package struct CompiledRefinementProgram: Sendable {
    package let name: String
    let instance: ModuleInstanceID
    let `operator`: RefinementDecl.Operator
    package let abstract: CompiledProgram
    package let variableMappings: [CompiledStateQuery]
}
