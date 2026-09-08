/// Expansion-time access to the same resolved program used by formal evaluation
/// and rendering. Generated machines consume Swift code emitted from this plan;
/// they do not store or interpret it at runtime.
package struct NativeMachinePlan: Sendable {
    package let variables: [CompiledVariableLayout]
    package let actionLayouts: [CompiledActionLayout]
    package let controlLocations: [CompiledControlLocation]
    package let initializations: [(variable: VariableID, initialization: CompiledVariableInitialization)]
    package let actions: [CompiledAction]
    package let invariants: [CompiledInvariant]
    package let constraint: CompiledStateExpr?
    package let assume: CompiledStateExpr?
    package let formalOperatorDefinitions: [CompiledFormalOperatorDefinition]
    package let recursiveFunctions: [CompiledRecursiveFunction]

    package init(compilation: CompiledSpecification) {
        variables = compilation.layout.variables
        actionLayouts = compilation.layout.actions
        controlLocations = compilation.layout.controlLocations
        initializations = compilation.semantics.variableInitializations
        actions = compilation.semantics.actions
        invariants = compilation.semantics.invariants
        constraint = compilation.semantics.constraint
        assume = compilation.semantics.assume
        formalOperatorDefinitions = compilation.semantics.formalOperatorDefinitions
        recursiveFunctions = compilation.semantics.recursiveFunctions
    }
}
