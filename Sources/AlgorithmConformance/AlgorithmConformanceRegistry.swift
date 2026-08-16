import SwiftTLA

/// One bounded Algorithm fixture that can be checked by independent external
/// lowerings. The fixture is deliberately separate from CoreConformance: it
/// establishes a narrow translation relationship, not project-wide support.
public struct AlgorithmConformanceFixture: Sendable {
    public let id: String
    /// The configuration for SwiftTLA's direct TLA+ lowering.
    public let swiftConfiguration: String
    /// The configuration for the module that the official PlusCal translator
    /// produces. It can require translator-introduced constants that do not
    /// exist in the direct lowering.
    public let plusCalConfiguration: String
    private let makeSpecification: @Sendable () -> TLASpec

    public init(
        id: String,
        swiftConfiguration: String,
        plusCalConfiguration: String? = nil,
        specification: @escaping @Sendable () -> TLASpec
    ) {
        self.id = id
        self.swiftConfiguration = swiftConfiguration
        self.plusCalConfiguration = plusCalConfiguration ?? swiftConfiguration
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
    public static let structuredRecordFunctions = AlgorithmConformanceFixture(
        id: "structured-record-functions",
        swiftConfiguration: "SPECIFICATION Spec\nCHECK_DEADLOCK FALSE\n",
        specification: { K4StructuredTLCWitness.spec }
    )

    public static let fixtures = [
        scopeBindingSubstitution,
        formalOperatorValues,
        simultaneousAssignment,
        structuredRecordFunctions,
        procedureCallReturn,
        boulangerUpstreamPort
    ]

    public static func fixture(id: String) -> AlgorithmConformanceFixture? {
        fixtures.first { $0.id == id }
    }
}
