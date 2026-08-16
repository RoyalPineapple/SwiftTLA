import SwiftTLA

/// One bounded Algorithm fixture that can be checked by independent external
/// lowerings. The fixture is deliberately separate from CoreConformance: it
/// establishes a narrow translation relationship, not project-wide support.
public struct AlgorithmConformanceFixture: Sendable {
    public let id: String
    public let configuration: String
    private let makeSpecification: @Sendable () -> TLASpec

    public init(
        id: String,
        configuration: String,
        specification: @escaping @Sendable () -> TLASpec
    ) {
        self.id = id
        self.configuration = configuration
        makeSpecification = specification
    }

    public func specification() -> TLASpec {
        makeSpecification()
    }

    /// Returns the single PlusCal module authored by this fixture.
    ///
    /// An oracle fixture intentionally has one source Algorithm: comparing a
    /// set of independent modules would obscure which lowering diverged.
    public func plusCalModule() throws -> String {
        let modules = try specification().renderAuthoredPlusCalModules()
        guard modules.count == 1 else {
            throw AlgorithmConformanceFixtureDiagnostic(
                failedConcept: "PlusCal oracle fixture source",
                fixtureID: id,
                expected: "exactly one authored Algorithm module",
                actual: "\(modules.count) authored Algorithm modules",
                systemChange: .none,
                nextSafeAction: "Give this oracle fixture one #spec Algorithm, or split independent Algorithms into separate fixtures."
            )
        }
        return modules[0]
    }
}

/// A typed diagnostic for fixture selection and source rendering.
public struct AlgorithmConformanceFixtureDiagnostic: Error, Sendable, Hashable, CustomStringConvertible {
    public enum SystemChange: String, Sendable, Hashable {
        case none
    }

    public let failedConcept: String
    public let fixtureID: String
    public let expected: String
    public let actual: String
    public let systemChange: SystemChange
    public let nextSafeAction: String

    public var description: String {
        "\(failedConcept) for '\(fixtureID)': expected \(expected); found \(actual). "
            + "System change: \(systemChange.rawValue). Next safe action: \(nextSafeAction)"
    }
}

/// The intentionally small initial corpus for the independent PlusCal oracle.
public enum AlgorithmConformanceRegistry {
    public static let k4StructuredDoors = AlgorithmConformanceFixture(
        id: "k4-structured-doors",
        configuration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K4StructuredTLCWitness.spec }
    )

    public static let fixtures = [
        k1ScopeBindingSubstitution,
        k2ScopedFormalLambda,
        k3SimultaneousAssignment,
        k4StructuredDoors,
        k5ProcedureCallReturn,
        k6BoulangerMC
    ]

    public static func fixture(id: String) -> AlgorithmConformanceFixture? {
        fixtures.first { $0.id == id }
    }
}
