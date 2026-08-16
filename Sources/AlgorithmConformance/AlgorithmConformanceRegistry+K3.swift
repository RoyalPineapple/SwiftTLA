import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// K3 isolates the PlusCal rule that assignments in one atomic step read
    /// the same old state and commit together.
    public static let k3SimultaneousAssignment = AlgorithmConformanceFixture(
        id: "k3-simultaneous-assignment",
        configuration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K3SimultaneousAssignmentWitness.spec }
    )
}
