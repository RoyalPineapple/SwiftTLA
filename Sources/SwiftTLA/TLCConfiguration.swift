/// TLC directives retained separately so validation can select checks without reparsing output.
package struct TLCConfiguration: Equatable, Sendable {
    package let declarations: [String]
    package let checkDeadlock: Bool
    package let invariants: [String]
    package let reachabilityProperties: [String]
    package let properties: [String]
    package let symmetry: [String]

    package init(declarations: [String], checkDeadlock: Bool, invariants: [String],
        reachabilityProperties: [String] = [], properties: [String], symmetry: [String]) {
        self.declarations = declarations
        self.checkDeadlock = checkDeadlock
        self.invariants = invariants
        self.reachabilityProperties = reachabilityProperties
        self.properties = properties
        self.symmetry = symmetry
    }

    func selecting(_ checks: Set<String>, checkDeadlock: Bool) throws -> Self {
        let unknown = checks.subtracting(invariants + reachabilityProperties + properties)
        guard unknown.isEmpty else {
            throw CompilationDiagnostic(
                code: .unknownReference, stage: .rendering, path: "TLC configuration",
                expected: "declared invariant or temporal property names",
                actual: unknown.sorted().joined(separator: ", "),
                nextSafeAction: "Select checks declared by this model."
            )
        }
        return Self(declarations: declarations, checkDeadlock: checkDeadlock,
            invariants: invariants.filter(checks.contains),
            reachabilityProperties: reachabilityProperties.filter(checks.contains),
            properties: properties.filter(checks.contains),
            symmetry: symmetry)
    }

    func render(usesSymmetryReduction: Bool) -> String {
        let header = ["SPECIFICATION Spec", checkDeadlock ? "CHECK_DEADLOCK TRUE" : "CHECK_DEADLOCK FALSE"]
        let checks = (invariants + reachabilityProperties).map { "INVARIANT \($0)" } + properties.map { "PROPERTY \($0)" }
        // TLC cannot soundly check liveness on a symmetry-reduced graph.
        let reduction = usesSymmetryReduction && properties.isEmpty ? symmetry.map { "SYMMETRY \($0)" } : []
        return (header + declarations + checks + reduction).joined(separator: "\n") + "\n"
    }
}
