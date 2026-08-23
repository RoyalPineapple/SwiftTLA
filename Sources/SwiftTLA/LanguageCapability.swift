public enum DeclaredLanguageConstruct: String, CaseIterable, Sendable, Hashable {
    case algorithm = "Algorithm"
    case sharedVariable = "SharedVar"
    case localVariable = "LocalVar"
    case each = "Each"
    case procedure = "Procedure"
    case atomicStep = "Do"
    case whileLoop = "While"
    case statementMacro = "Macro"
    case awaitCondition = "Await"
    case assertion = "Assert"
    case assignment = "Assign"
    case letBinding = "Let"
    case withBinding = "With"
    case ifElse = "If"
    case either = "Either"
    case choose = "Choose"
    case goto = "Goto"
    case call = "Call"
    case `return` = "Return"
    case stop = "Stop"
    case skip = "Skip"
    case invariant = "Invariant"
    case temporalProperty = "Temporal property"
    case processFairness = "Each fairness"
    case stateConstraint = "StateConstraint"
    case formalDefinition = "FormalDefinition"
    case genericFairness = "WeakFairness / StrongFairness"
    case sequentialAlgorithmFairness = "Algorithm fairness"
    case algorithmAssume = "Assume in Algorithm"
    case algorithmTheorem = "Theorem in Algorithm"
    case temporalRefinementLiveSpec = ".liveSpec refinement"
    case temporalRefinementLiveSpecEquals = ".liveSpecEquals refinement"

}

public enum LanguageCapabilityStatus: String, Sendable, Hashable {
    case supported
    case unsupported
}

public enum LanguageCapabilityDimension: String, CaseIterable, Sendable, Hashable {
    case sourceDecoding
    case resultBuilderConstruction
    case compilation
    case tlaRendering
    case plusCalRendering
    case execution
    case boundedConformance
}

public enum LanguageCapabilityDimensionStatus: String, Sendable, Hashable {
    case supported
    case unsupported
    case notApplicable
}

public struct LanguageCapabilityDimensions: Sendable, Hashable {
    public let sourceDecoding: LanguageCapabilityDimensionStatus
    public let resultBuilderConstruction: LanguageCapabilityDimensionStatus
    public let compilation: LanguageCapabilityDimensionStatus
    public let tlaRendering: LanguageCapabilityDimensionStatus
    public let plusCalRendering: LanguageCapabilityDimensionStatus
    public let execution: LanguageCapabilityDimensionStatus
    public let boundedConformance: LanguageCapabilityDimensionStatus

    public init(
        sourceDecoding: LanguageCapabilityDimensionStatus,
        resultBuilderConstruction: LanguageCapabilityDimensionStatus,
        compilation: LanguageCapabilityDimensionStatus,
        tlaRendering: LanguageCapabilityDimensionStatus,
        plusCalRendering: LanguageCapabilityDimensionStatus,
        execution: LanguageCapabilityDimensionStatus,
        boundedConformance: LanguageCapabilityDimensionStatus
    ) {
        self.sourceDecoding = sourceDecoding
        self.resultBuilderConstruction = resultBuilderConstruction
        self.compilation = compilation
        self.tlaRendering = tlaRendering
        self.plusCalRendering = plusCalRendering
        self.execution = execution
        self.boundedConformance = boundedConformance
    }

    public subscript(_ dimension: LanguageCapabilityDimension) -> LanguageCapabilityDimensionStatus? {
        switch dimension {
        case .sourceDecoding: sourceDecoding
        case .resultBuilderConstruction: resultBuilderConstruction
        case .compilation: compilation
        case .tlaRendering: tlaRendering
        case .plusCalRendering: plusCalRendering
        case .execution: execution
        case .boundedConformance: boundedConformance
        }
    }
}

public struct LanguageCapability: Sendable, Hashable {
    public let construct: DeclaredLanguageConstruct
    public let status: LanguageCapabilityStatus
    public let dimensions: LanguageCapabilityDimensions
    public let boundary: String
    public let nextSafeAction: String

    public init(
        construct: DeclaredLanguageConstruct,
        status: LanguageCapabilityStatus,
        dimensions: LanguageCapabilityDimensions,
        boundary: String,
        nextSafeAction: String
    ) {
        self.construct = construct
        self.status = status
        self.dimensions = dimensions
        self.boundary = boundary
        self.nextSafeAction = nextSafeAction
    }
}

public enum LanguageConstructReference: Sendable, Hashable {
    case declared(construct: DeclaredLanguageConstruct, authoredName: String)
    case unregistered(sourceName: String)

    public var construct: DeclaredLanguageConstruct? {
        guard case .declared(let construct, _) = self else { return nil }
        return construct
    }

    public var authoredName: String {
        switch self {
        case .declared(_, let authoredName), .unregistered(let authoredName): authoredName
        }
    }
}

public enum LanguageCapabilityLedgerError: Error, Sendable, Hashable {
    case duplicateRecord(DeclaredLanguageConstruct)
    case missingRecord(DeclaredLanguageConstruct)
    case unsupportedCompilation(DeclaredLanguageConstruct)
    case supportedCapabilityWithoutConstructionRoute(DeclaredLanguageConstruct)
}

public enum LanguageCapabilityLedger {
    public static let all: [LanguageCapability] = {
        let records = DeclaredLanguageConstruct.allCases.map(record(for:))
        do {
            try validate(records)
        } catch {
            preconditionFailure("Language capability ledger invariant failed: \(error)")
        }
        return records
    }()

    public static func capability(for construct: DeclaredLanguageConstruct) -> LanguageCapability {
        guard let capability = all.first(where: { $0.construct == construct }) else {
            preconditionFailure("Language capability ledger omitted \(construct.rawValue).")
        }
        return capability
    }

    public static func capability(for reference: LanguageConstructReference) -> LanguageCapability? {
        guard case .declared(let construct, _) = reference else { return nil }
        return capability(for: construct)
    }

    public static func validate(_ records: [LanguageCapability]) throws {
        var constructs = Set<DeclaredLanguageConstruct>()
        for record in records {
            guard constructs.insert(record.construct).inserted else {
                throw LanguageCapabilityLedgerError.duplicateRecord(record.construct)
            }
            if record.status == .unsupported, record.dimensions.compilation == .supported {
                throw LanguageCapabilityLedgerError.unsupportedCompilation(record.construct)
            }
            if record.status == .supported,
               record.dimensions.sourceDecoding != .supported,
               record.dimensions.resultBuilderConstruction != .supported {
                throw LanguageCapabilityLedgerError.supportedCapabilityWithoutConstructionRoute(record.construct)
            }
        }
        for construct in DeclaredLanguageConstruct.allCases where !constructs.contains(construct) {
            throw LanguageCapabilityLedgerError.missingRecord(construct)
        }
    }

    private static func record(for construct: DeclaredLanguageConstruct) -> LanguageCapability {
        switch construct {
        case .genericFairness:
            unsupportedRecord(
                construct,
                sourceDecoding: .supported,
                resultBuilderConstruction: .supported,
                boundary: "Generic TLA fairness is not admitted inside Algorithm.",
                nextSafeAction: "Use Algorithm(..., fairness:) for sequential fairness or Each(..., fairness:) for process fairness."
            )
        case .algorithmAssume, .algorithmTheorem:
            unsupportedRecord(
                construct,
                sourceDecoding: .supported,
                resultBuilderConstruction: .supported,
                boundary: "Assume and Theorem are not admitted inside Algorithm.",
                nextSafeAction: "Place the declaration outside Algorithm in the formal specification."
            )
        case .temporalRefinementLiveSpec, .temporalRefinementLiveSpecEquals:
            unsupportedRecord(
                construct,
                sourceDecoding: .supported,
                resultBuilderConstruction: .notApplicable,
                boundary: "Live specification refinement targets are not admitted by the initial Algorithm ledger.",
                nextSafeAction: "Use an explicitly admitted temporal property."
            )
        case .algorithm, .sharedVariable, .localVariable, .each, .procedure, .atomicStep,
             .whileLoop, .statementMacro, .awaitCondition, .assertion, .assignment,
             .letBinding, .withBinding, .ifElse, .either, .choose, .goto, .call,
             .return, .stop, .skip, .invariant, .temporalProperty, .processFairness,
             .stateConstraint, .formalDefinition, .sequentialAlgorithmFairness:
            LanguageCapability(
                construct: construct,
                status: .supported,
                dimensions: .init(
                    sourceDecoding: .supported,
                    resultBuilderConstruction: .supported,
                    compilation: .supported,
                    tlaRendering: .supported,
                    plusCalRendering: .supported,
                    execution: .supported,
                    boundedConformance: .supported
                ),
                boundary: "Admitted in the PlusCal-shaped Algorithm authoring surface.",
                nextSafeAction: "Use the typed authoring API within its declared Algorithm placement."
            )
        }
    }

    private static func unsupportedRecord(
        _ construct: DeclaredLanguageConstruct,
        sourceDecoding: LanguageCapabilityDimensionStatus,
        resultBuilderConstruction: LanguageCapabilityDimensionStatus,
        boundary: String,
        nextSafeAction: String
    ) -> LanguageCapability {
        LanguageCapability(
            construct: construct,
            status: .unsupported,
            dimensions: .init(
                sourceDecoding: sourceDecoding,
                resultBuilderConstruction: resultBuilderConstruction,
                compilation: .unsupported,
                tlaRendering: .notApplicable,
                plusCalRendering: .notApplicable,
                execution: .notApplicable,
                boundedConformance: .notApplicable
            ),
            boundary: boundary,
            nextSafeAction: nextSafeAction
        )
    }
}
