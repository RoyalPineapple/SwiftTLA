extension ModelBehavior {
    var directives: [String] {
        switch self {
        case .specification: ["SPECIFICATION Spec"]
        case .initialAndNext: ["INIT Init", "NEXT Next"]
        }
    }
}

/// TLC directives retained separately so validation can select checks without reparsing output.
package struct TLCConfiguration: Equatable, Sendable {
    package let behavior: ModelBehavior
    package let declarations: [String]
    package let checkDeadlock: Bool
    package let invariants: [String]
    package let reachabilityProperties: [String]
    package let properties: [String]
    package let refinements: [String]
    package let symmetry: [String]

    package init(behavior: ModelBehavior = .specification, declarations: [String], checkDeadlock: Bool, invariants: [String],
        reachabilityProperties: [String] = [], properties: [String], refinements: [String] = [], symmetry: [String]) {
        self.behavior = behavior
        self.declarations = declarations
        self.checkDeadlock = checkDeadlock
        self.invariants = invariants
        self.reachabilityProperties = reachabilityProperties
        self.properties = properties
        self.refinements = refinements
        self.symmetry = symmetry
    }

    func selecting(_ checks: Set<String>, checkDeadlock: Bool, behavior: ModelBehavior? = nil) throws -> Self {
        let unknown = checks.subtracting(invariants + reachabilityProperties + properties + refinements)
        guard unknown.isEmpty else {
            throw CompilationDiagnostic(
                code: .unknownReference, stage: .rendering, path: "TLC configuration",
                expected: "declared invariant or temporal property names",
                actual: unknown.sorted().joined(separator: ", "),
                nextSafeAction: "Select checks declared by this model."
            )
        }
        return Self(behavior: behavior ?? self.behavior, declarations: declarations, checkDeadlock: checkDeadlock,
            invariants: invariants.filter(checks.contains),
            reachabilityProperties: reachabilityProperties.filter(checks.contains),
            properties: properties.filter(checks.contains),
            refinements: refinements.filter(checks.contains),
            symmetry: symmetry)
    }

    func render(usesSymmetryReduction: Bool) -> String {
        let header = behavior.directives + [checkDeadlock ? "CHECK_DEADLOCK TRUE" : "CHECK_DEADLOCK FALSE"]
        let checks = (invariants + reachabilityProperties).map { "INVARIANT \($0)" } + (properties + refinements).map { "PROPERTY \($0)" }
        // TLC cannot soundly check liveness on a symmetry-reduced graph.
        let reduction = usesSymmetryReduction && properties.isEmpty && refinements.isEmpty ? symmetry.map { "SYMMETRY \($0)" } : []
        return (header + declarations + checks + reduction).joined(separator: "\n") + "\n"
    }
}
