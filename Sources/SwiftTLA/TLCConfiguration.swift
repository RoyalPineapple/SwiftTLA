struct TLCModuleReplacement: Equatable, Sendable {
    let moduleName: String
    let operatorName: String
    let definitionName: String
}

extension CompiledFormalModuleReplacement {
    func configuration(moduleNames: [String: String] = [:]) -> TLCModuleReplacement {
        .init(moduleName: moduleNames[moduleName] ?? moduleName,
            operatorName: operatorName, definitionName: definitionName)
    }
}

extension ModelBehavior {
    func directives(specificationName: String) -> [String] {
        switch self {
        case .specification: ["SPECIFICATION \(specificationName)"]
        case .initialAndNext: ["INIT Init", "NEXT Next"]
        }
    }
}

/// TLC directives retained separately so validation can select checks without reparsing output.
package struct TLCConfiguration: Equatable, Sendable {
    package let behavior: ModelBehavior
    package let specificationName: String
    package let assumptionsOnly: Bool
    package let declarations: [String]
    package let checkDeadlock: Bool
    package let invariants: [String]
    package let reachabilityProperties: [String]
    package let properties: [String]
    package let refinements: [String]
    package let symmetry: [String]
    package let viewOperators: [String]
    package let view: String?

    package init(behavior: ModelBehavior = .specification, specificationName: String = "Spec",
        assumptionsOnly: Bool = false,
        declarations: [String], checkDeadlock: Bool, invariants: [String],
        reachabilityProperties: [String] = [], properties: [String], refinements: [String] = [], symmetry: [String],
        viewOperators: [String] = [], view: String? = nil) {
        self.behavior = behavior
        self.specificationName = specificationName
        self.assumptionsOnly = assumptionsOnly
        self.declarations = declarations
        self.checkDeadlock = checkDeadlock
        self.invariants = invariants
        self.reachabilityProperties = reachabilityProperties
        self.properties = properties
        self.refinements = refinements
        self.symmetry = symmetry
        self.viewOperators = viewOperators
        self.view = view
    }

    func selecting(_ checks: Set<String>, checkDeadlock: Bool, behavior: ModelBehavior? = nil,
        specificationName: String? = nil) throws -> Self {
        if assumptionsOnly && (!checks.isEmpty || checkDeadlock) {
            throw CompilationDiagnostic(
                code: .unknownReference, stage: .rendering, path: "TLC configuration",
                expected: "no state properties or deadlock check for an assumption-only module",
                actual: "state check selected",
                nextSafeAction: "Evaluate the module assumptions without a state-machine check."
            )
        }
        let unknown = checks.subtracting(invariants + reachabilityProperties + properties + refinements)
        guard unknown.isEmpty else {
            throw CompilationDiagnostic(
                code: .unknownReference, stage: .rendering, path: "TLC configuration",
                expected: "declared invariant or temporal property names",
                actual: unknown.sorted().joined(separator: ", "),
                nextSafeAction: "Select checks declared by this model."
            )
        }
        return Self(behavior: behavior ?? self.behavior,
            specificationName: specificationName ?? self.specificationName, assumptionsOnly: assumptionsOnly,
            declarations: declarations, checkDeadlock: checkDeadlock,
            invariants: invariants.filter(checks.contains),
            reachabilityProperties: reachabilityProperties.filter(checks.contains),
            properties: properties.filter(checks.contains),
            refinements: refinements.filter(checks.contains),
            symmetry: symmetry, viewOperators: viewOperators, view: view)
    }

    func selectingSymmetry(_ name: String?) throws -> Self {
        if let name {
            guard symmetry.contains(name) else {
                throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                    path: "symmetry selection", expected: "a declared symmetry operator",
                    actual: name, nextSafeAction: "Select a symmetry declared by this model.")
            }
            try validateSymmetryChecks()
        }
        return Self(behavior: behavior, specificationName: specificationName, assumptionsOnly: assumptionsOnly,
            declarations: declarations, checkDeadlock: checkDeadlock,
            invariants: invariants, reachabilityProperties: reachabilityProperties,
            properties: properties, refinements: refinements,
            symmetry: name.map { [$0] } ?? [], viewOperators: viewOperators, view: view)
    }

    func selectingView(_ name: String?) throws -> Self {
        if let name, !viewOperators.contains(name) {
            throw CompilationDiagnostic(code: .unknownReference, stage: .rendering,
                path: "view selection", expected: "a declared view operator", actual: name,
                nextSafeAction: "Select a view declared by this model.")
        }
        return Self(behavior: behavior, specificationName: specificationName, assumptionsOnly: assumptionsOnly,
            declarations: declarations, checkDeadlock: checkDeadlock,
            invariants: invariants, reachabilityProperties: reachabilityProperties,
            properties: properties, refinements: refinements, symmetry: symmetry,
            viewOperators: viewOperators, view: name)
    }

    func usesSupportedSymmetryReduction(_ reduction: SymmetryReduction) throws -> Bool {
        guard case .enabled(let maximumPermutationCount) = reduction else { return false }
        guard maximumPermutationCount > 0 else {
            throw CompilationDiagnostic(code: .unsupportedSymmetryReduction, stage: .rendering,
                path: "symmetryReduction", expected: "a positive permutation limit",
                actual: "\(maximumPermutationCount)", nextSafeAction: "Use a positive permutation limit.")
        }
        guard !symmetry.isEmpty else {
            throw CompilationDiagnostic(code: .unsupportedSymmetryReduction, stage: .rendering,
                path: "symmetryReduction", expected: "an explicit symmetry declaration",
                actual: "none", nextSafeAction: "Declare interchangeable members or disable symmetry reduction.")
        }
        try validateSymmetryChecks()
        return true
    }

    private func validateSymmetryChecks() throws {
        guard properties.isEmpty && refinements.isEmpty else {
            throw CompilationDiagnostic(code: .unsupportedSymmetryReduction, stage: .rendering,
                path: "symmetryReduction", expected: "safety-only selected checks",
                actual: "temporal or refinement properties selected",
                nextSafeAction: "Run those checks on the complete, unreduced graph.")
        }
    }

    func render(usesSymmetryReduction: Bool) -> String {
        if assumptionsOnly { return declarations.joined(separator: "\n") + (declarations.isEmpty ? "" : "\n") }
        let header = behavior.directives(specificationName: specificationName)
            + [checkDeadlock ? "CHECK_DEADLOCK TRUE" : "CHECK_DEADLOCK FALSE"]
        let checks = (invariants + reachabilityProperties).map { "INVARIANT \($0)" } + (properties + refinements).map { "PROPERTY \($0)" }
        // TLC cannot soundly check liveness on a symmetry-reduced graph.
        let reduction = usesSymmetryReduction && properties.isEmpty && refinements.isEmpty ? symmetry.map { "SYMMETRY \($0)" } : []
        return (header + declarations + checks + reduction + (view.map { ["VIEW \($0)"] } ?? [])).joined(separator: "\n") + "\n"
    }
}
