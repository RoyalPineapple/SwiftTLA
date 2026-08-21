@testable import SwiftTLA

func compiledSourceSpecification(_ algorithm: Algorithm) throws -> TLASpec {
    try TLASpec(algorithm.model.name) { algorithm }.compile().spec
}

func renderedSourceAlgorithmPlusCal(_ algorithm: Algorithm) throws -> String {
    try TLASpec(algorithm.model.name) { algorithm }
        .compile()
        .renderedPlusCalBundle()
        .root
        .tla
}

func canonicalTestSpec(
    variables: [(name: String, initial: TLAValue, initialSet: StateExpr?)] = [],
    actions: [(name: String, body: ActionExpr, bindings: [ActionBinding])] = [],
    invariants: [(name: String, body: StateExpr)] = [],
    temporal: [(name: String, expr: TemporalExpr)] = [],
    fairness: [FairnessCondition] = [],
    constraint: StateExpr? = nil,
    imports: [String] = [],
    importConfigurations: [FormalModuleConfiguration] = [],
    moduleInstances: [FormalModuleInstance] = [],
    formalParameters: [FormalModuleParameter] = [],
    formalOperatorDefinitions: [FormalOperatorDefinition] = [],
    definitions: [DirectModuleDefinition] = [],
    symmetrySets: [SymmetrySet] = []
) -> TLASpec {
    TLASpec(
        name: "CanonicalTestSpec",
        variables: variables.map {
            NamedVar(name: $0.name, initial: $0.initial, initialSet: $0.initialSet)
        },
        formalParameters: formalParameters,
        actions: actions.map {
            NamedAction(name: $0.name, body: $0.body, bindings: $0.bindings)
        },
        invariants: invariants.map { NamedInvariant(name: $0.name, body: $0.body) },
        temporalProperties: temporal.map { NamedTemporal(name: $0.name, expr: $0.expr) },
        fairness: fairness,
        definitions: definitions,
        constraint: constraint,
        formalOperatorDefinitions: formalOperatorDefinitions,
        imports: imports.compactMap(FormalModuleRegistry.lookup),
        importConfigurations: importConfigurations,
        moduleInstances: moduleInstances,
        symmetrySets: symmetrySets
    )
}
