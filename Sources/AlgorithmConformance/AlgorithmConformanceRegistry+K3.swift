import SwiftTLA

extension AlgorithmConformanceRegistry {
    /// Assignments in one atomic step read the same old state and commit
    /// together.
    public static let simultaneousAssignment = AlgorithmConformanceFixture(
        id: "simultaneous-assignment",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K3SimultaneousAssignmentWitness.spec }
    )
}
