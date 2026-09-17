import CryptoKit
import Foundation
import SwiftTLA

package enum FiniteGraphCaseError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case invalidSHA256(field: String)
    case invalidRenderedActions
    case moduleDigestMismatch
    case cfgDigestMismatch
    case pinMismatch(String)
    case missingArtifact(String)
    case symmetryGeneratorsWithoutReduction
}

package struct TLCReferencePin: Equatable, Sendable {
    package let tag: String
    package let commit: String
    package let jarSHA256: String
    package let javaDistribution: String
    package let javaVersion: String
    package let javaArchiveSHA256: String
    package let bridgeClass: String
    package let bridgeSourceHashes: [String: String]
    package let bridgeBinarySHA256: String

    package init(
        tag: String,
        commit: String,
        jarSHA256: String,
        javaDistribution: String,
        javaVersion: String,
        javaArchiveSHA256: String,
        bridgeClass: String,
        bridgeSourceHashes: [String: String],
        bridgeBinarySHA256: String
    ) throws {
        guard !tag.isEmpty, Self.isRevision(commit) else {
            throw FiniteGraphCaseError.invalidIdentifier("TLC release")
        }
        guard !javaDistribution.isEmpty, !javaVersion.isEmpty else {
            throw FiniteGraphCaseError.invalidIdentifier("Java runtime")
        }
        guard !bridgeClass.isEmpty else {
            throw FiniteGraphCaseError.invalidIdentifier("bridge class")
        }
        for (field, value) in [
            ("jarSHA256", jarSHA256), ("javaArchiveSHA256", javaArchiveSHA256),
            ("bridgeBinarySHA256", bridgeBinarySHA256)
        ] where !Self.isSHA256(value) {
            throw FiniteGraphCaseError.invalidSHA256(field: field)
        }
        guard !bridgeSourceHashes.isEmpty else { throw FiniteGraphCaseError.missingArtifact("bridge sources") }
        for (path, hash) in bridgeSourceHashes {
            guard !path.isEmpty, Self.isSHA256(hash) else {
                throw FiniteGraphCaseError.invalidSHA256(field: "bridge source " + path)
            }
        }
        self.tag = tag
        self.commit = commit
        self.jarSHA256 = jarSHA256
        self.javaDistribution = javaDistribution
        self.javaVersion = javaVersion
        self.javaArchiveSHA256 = javaArchiveSHA256
        self.bridgeClass = bridgeClass
        self.bridgeSourceHashes = bridgeSourceHashes
        self.bridgeBinarySHA256 = bridgeBinarySHA256
    }

    package static let standardModuleNames: Set<String> = [
        "Bags", "FiniteSets", "Integers", "Json", "Naturals", "Randomization", "RealTime",
        "Reals", "Sequences", "TLC", "TLCExt", "Toolbox", "_DotTrace", "_JsonTrace",
        "_Possible", "_TLAPlusCounterExample", "_TLCActionTrace", "_TLCTESpec", "_TLCTrace",
        "_TLCTracePlain"
    ]


    package func validate(_ artifacts: TLCReferenceArtifacts) throws {
        try Self.verify(artifacts.jar, expected: jarSHA256, name: "TLC JAR")
        guard artifacts.jarManifest.contains("Implementation-Title: TLA+ Tools"),
              artifacts.jarManifest.contains("X-Git-Revision: \(commit)")
        else { throw FiniteGraphCaseError.pinMismatch("TLC JAR manifest") }
        guard artifacts.runtime.version == javaVersion,
              artifacts.runtime.vendor.contains("Eclipse Adoptium"),
              artifacts.runtime.properties["java.runtime.version"] == javaVersion,
              artifacts.runtime.properties["java.vendor"]?.contains("Eclipse Adoptium") == true
        else { throw FiniteGraphCaseError.pinMismatch("Java runtime") }
        guard !artifacts.runtime.architecture.isEmpty else {
            throw FiniteGraphCaseError.pinMismatch("Java architecture")
        }
        try Self.verify(artifacts.javaArchive, expected: javaArchiveSHA256, name: "Java archive")
        try Self.verify(artifacts.bridgeBinary, expected: bridgeBinarySHA256, name: "bridge binary")
        guard Set(artifacts.bridgeSources.keys) == Set(bridgeSourceHashes.keys) else {
            throw FiniteGraphCaseError.pinMismatch("bridge source inventory")
        }
        for (path, hash) in bridgeSourceHashes {
            guard let source = artifacts.bridgeSources[path] else { throw FiniteGraphCaseError.missingArtifact(path) }
            try Self.verify(source, expected: hash, name: "bridge source " + path)
        }
    }

    package func validateReportedTLCBanner(_ output: String) throws {
        let revision = String(commit.prefix(7))
        guard output.split(whereSeparator: \.isNewline).contains(where: {
            $0.contains("TLC2 Version") && $0.contains("(rev: \(revision))")
        }) else {
            throw FiniteGraphCaseError.pinMismatch("TLC banner")
        }
    }

    private static func verify(_ file: URL, expected: String, name: String) throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw FiniteGraphCaseError.missingArtifact(name)
        }
        guard SHA256.hex(try Data(contentsOf: file)) == expected else {
            throw FiniteGraphCaseError.pinMismatch(name)
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    static func isRevision(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
    }
}

package struct FiniteGraphCase: Equatable, Sendable {
    package let id: String
    package let exploration: FiniteExplorationConfiguration
    package let moduleSHA256: String
    package let cfgSHA256: String
    package let arguments: [String]
    package let environment: [String: String]
    package let pin: TLCReferencePin
    package let renderedActions: [RenderedAction]
    let symmetryGroup: [SymmetryPermutation]

    package init(
        id: String,
        exploration: FiniteExplorationConfiguration,
        moduleSHA256: String,
        cfgSHA256: String,
        arguments: [String],
        environment: [String: String],
        pin: TLCReferencePin,
        renderedActions: [RenderedAction] = [],
        symmetryGenerators: [SymmetryPermutation] = []
    ) throws {
        guard !id.isEmpty else { throw FiniteGraphCaseError.invalidIdentifier("case ID") }
        guard TLCReferencePin.isSHA256(moduleSHA256) else { throw FiniteGraphCaseError.invalidSHA256(field: "moduleSHA256") }
        guard TLCReferencePin.isSHA256(cfgSHA256) else { throw FiniteGraphCaseError.invalidSHA256(field: "cfgSHA256") }
        guard Set(renderedActions.map(\.sourceInvocationName)).count == renderedActions.count,
              Set(renderedActions.map(\.renderedName)).count == renderedActions.count else {
            throw FiniteGraphCaseError.invalidRenderedActions
        }
        self.id = id
        self.exploration = exploration
        self.moduleSHA256 = moduleSHA256
        self.cfgSHA256 = cfgSHA256
        self.arguments = arguments
        self.environment = environment
        self.pin = pin
        self.renderedActions = renderedActions
        switch exploration.symmetryReduction {
        case .disabled:
            guard symmetryGenerators.isEmpty else {
                throw FiniteGraphCaseError.symmetryGeneratorsWithoutReduction
            }
            symmetryGroup = []
        case .enabled(let maximumPermutationCount):
            symmetryGroup = try SymmetryPermutation.closedGroup(
                generatedBy: symmetryGenerators,
                maximumPermutationCount: maximumPermutationCount)
        }
    }

    package func validateLaunch(module: URL, configuration: URL) throws {
        guard SHA256.hex(try Data(contentsOf: module)) == moduleSHA256 else {
            throw FiniteGraphCaseError.moduleDigestMismatch
        }
        guard SHA256.hex(try Data(contentsOf: configuration)) == cfgSHA256 else {
            throw FiniteGraphCaseError.cfgDigestMismatch
        }
    }
}

func tlaInvocationLocationIdentity(action: String, arguments: [String]) -> String {
    "\(action)(\(arguments.map(tlaLocationArgumentIdentity).joined(separator: ",")))"
}

func tlaLocationArgumentIdentity(_ argument: String) -> String {
    var identity = String()
    var quoted = false
    var escaped = false
    for character in argument.trimmingCharacters(in: .whitespacesAndNewlines) {
        if quoted {
            identity.append(character)
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted = false
            }
        } else if character == "\"" {
            quoted = true
            identity.append(character)
        } else if !character.isWhitespace {
            identity.append(character)
        }
    }
    return identity
}

/// The source-controlled declaration for a finite conformance case.
package struct FiniteGraphManifest: Decodable, Sendable {
    private static let schema = "FiniteGraphCases"

    private let schema: String
    package let cases: [Case]

    package struct Case: Decodable, Sendable {
        package let sourceModel: FiniteGraphSourceModel
        package let scenario: String?
        package let id: String
        package let module: String
        package let configuration: String
        package let imports: [String]
        package let dependencies: [Dependency]
        package let sourceInput: SourceInputPin?
        package let moduleSHA256: String
        package let cfgSHA256: String
        package let exploration: FiniteExplorationConfiguration
        package let timeoutSeconds: TimeInterval

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, sourceModel, scenario, module, configuration, imports, dependencies, sourceInput, moduleSHA256, cfgSHA256, exploration, timeoutSeconds
        }

        package struct Dependency: Decodable, Sendable {
            package let importingModule: String
            package let importedModule: String

            private enum CodingKeys: String, CodingKey, CaseIterable {
                case importingModule, importedModule
            }

            package init(from decoder: Decoder) throws {
                let container = try decoder.container(validatingKeys: CodingKeys.self)
                importingModule = try container.decode(String.self, forKey: .importingModule)
                importedModule = try container.decode(String.self, forKey: .importedModule)
            }
        }

        package init(from decoder: Decoder) throws {
            let container = try decoder.container(validatingKeys: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            sourceModel = try container.decode(FiniteGraphSourceModel.self, forKey: .sourceModel)
            scenario = try container.decodeIfPresent(String.self, forKey: .scenario)
            module = try container.decode(String.self, forKey: .module)
            configuration = try container.decode(String.self, forKey: .configuration)
            imports = try container.decode([String].self, forKey: .imports)
            dependencies = try container.decode([Dependency].self, forKey: .dependencies)
            sourceInput = try container.decodeIfPresent(SourceInputPin.self, forKey: .sourceInput)
            moduleSHA256 = try container.decode(String.self, forKey: .moduleSHA256)
            cfgSHA256 = try container.decode(String.self, forKey: .cfgSHA256)
            timeoutSeconds = try container.decode(TimeInterval.self, forKey: .timeoutSeconds)
            exploration = try container.decode(
                FiniteExplorationConfiguration.self,
                forKey: .exploration
            )
            try validate()
        }

        package func resolveScenario() throws -> (any ModelValidationScenario)? {
            let scenarios: [any ModelValidationScenario]
            switch sourceModel {
            case .diningPhilosophers:
                scenarios = try DiningPhilosophersModel.validationScenarios()
            case .hourClock:
                scenarios = try HourClockModel.validationScenarios()
            case .hourClock2:
                scenarios = try HourClock2Model.validationScenarios()
            case .leastCircularSubstring:
                scenarios = try LeastCircularSubstringModel.validationScenarios()
            case .dieHard:
                scenarios = try DieHardModel.validationScenarios()
            case .dieHarder:
                scenarios = try DieHarderModel.validationScenarios()
            case .channel:
                scenarios = try ChannelModel.validationScenarios()
            default:
                guard scenario == nil else {
                    throw EvidenceFormatError.invalidField(record: id, field: "model-owned scenario")
                }
                return nil
            }
            let matches = scenarios.filter { $0.name == scenario }
            guard matches.count == 1 else {
                throw EvidenceFormatError.invalidField(record: id, field: "model-owned scenario")
            }
            return matches[0]
        }

        private func validate() throws {
            let allowedIDCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
            guard !id.isEmpty, id != "all", id.unicodeScalars.allSatisfy(allowedIDCharacters.contains) else {
                throw FiniteGraphCaseError.invalidIdentifier("case ID")
            }
            guard timeoutSeconds.isFinite, timeoutSeconds > 0 else {
                throw EvidenceFormatError.invalidField(record: id, field: "timeoutSeconds")
            }
            guard module.isEmpty == false, configuration.isEmpty == false,
                  Set(imports).count == imports.count, imports.allSatisfy({ $0.isEmpty == false }),
                  dependencies.allSatisfy({
                      $0.importingModule.isEmpty == false && $0.importedModule.isEmpty == false
                  }) else {
                throw EvidenceFormatError.invalidField(record: id, field: "case declaration")
            }
            guard case .disabled = exploration.symmetryReduction else {
                throw EvidenceFormatError.invalidField(
                    record: id,
                    field: "exploration.symmetryReduction"
                )
            }
            guard TLCReferencePin.isSHA256(moduleSHA256), TLCReferencePin.isSHA256(cfgSHA256) else {
                throw EvidenceFormatError.invalidField(record: id, field: "launch contract")
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, cases }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(validatingKeys: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        cases = try container.decode([Case].self, forKey: .cases)
        try validate()
    }

    package func validate() throws {
        guard schema == Self.schema, !cases.isEmpty else {
            throw EvidenceFormatError.invalidSchema(schema)
        }
        var caseIDs = Set<String>()
        for finiteGraphCase in cases {
            guard caseIDs.insert(finiteGraphCase.id).inserted else {
                throw EvidenceFormatError.duplicateID(
                    kind: "finite graph case",
                    id: finiteGraphCase.id
                )
            }
        }
    }

}

package enum FiniteGraphSourceModel: String, CaseIterable, Decodable, Hashable, Sendable {
    case channel
    case majority
    case boulanger
    case voteProof = "voteproof"
    case kvsnap
    case asynchInterface = "asynch-interface"
    case hourClock = "hour-clock"
    case hourClock2 = "hour-clock-2"
    case leastCircularSubstring = "least-circular-substring"
    case dieHard = "die-hard"
    case dieHarder = "die-harder"
    case multiCarElevator = "multicar-elevator"
    case tlcmcGraph1 = "tlcmc-graph-1"
    case nQueensFour = "n-queens-four"
    case diningPhilosophers = "dining-philosophers"
    case stringLiterals = "string-literals"
    case actionReferences = "action-references"

    package func nativeRun(rendered: RenderedSpecification, checkingDeadlock: Bool,
        scenario: (any ModelValidationScenario)? = nil, for finiteGraphCase: FiniteGraphCase) throws -> NativeModelRun {
        func exploreScenario<Scenario: ModelValidationScenario>(_ scenario: Scenario) throws -> NativeModelRun {
            try NativeModelRun(scenario.explore(maximumStates: finiteGraphCase.exploration.maximumStateLimit),
                rendered: rendered, checkingDeadlock: checkingDeadlock, for: finiteGraphCase)
        }
        if let scenario { return try exploreScenario(scenario) }
        func explore<Machine: StateMachine>(_ initial: [Machine]) throws -> NativeModelRun {
            try NativeModelRun(ReachabilityGraph(initialMachines: initial,
                maximumStates: finiteGraphCase.exploration.maximumStateLimit),
                rendered: rendered, checkingDeadlock: checkingDeadlock, for: finiteGraphCase)
        }
        switch self {
        case .boulanger: return try explore(BoulangerModel.initialMachines())
        case .voteProof: return try explore(VoteProofModel.initialMachines())
        case .kvsnap: return try explore(KVsnapModel.initialMachines())
        case .majority: return try explore(MajorityModel.initialMachines())
        case .asynchInterface: return try explore(AsynchInterfaceModel.initialMachines())
        case .multiCarElevator: return try explore(MultiCarElevator.initialMachines())
        case .tlcmcGraph1: return try explore(TLCMCModel.initialMachines())
        case .nQueensFour: return try explore(NQueensModel.initialMachines())
        case .diningPhilosophers, .hourClock, .hourClock2, .leastCircularSubstring, .dieHard, .dieHarder, .channel:
            throw EvidenceFormatError.invalidField(record: finiteGraphCase.id, field: "model-owned scenario")
        case .stringLiterals: return try explore(StringLiteralModel.initialMachines())
        case .actionReferences: return try explore(ActionReferencesModel.initialMachines())
        }
    }

    package var spec: TLASpec {
        switch self {
        case .boulanger: BoulangerModel.spec
        case .voteProof: VoteProofModel.spec
        case .kvsnap: KVsnapModel.spec
        case .majority: MajorityModel.spec
        case .channel: ChannelModel.spec
        case .asynchInterface: AsynchInterfaceModel.spec
        case .hourClock: Example.hourClock.spec
        case .hourClock2: HourClock2Model.spec
        case .leastCircularSubstring: LeastCircularSubstringModel.spec
        case .dieHard: DieHardModel.spec
        case .dieHarder: DieHarderModel.spec
        case .multiCarElevator: MultiCarElevator.spec
        case .tlcmcGraph1: TLCMCModel.spec
        case .nQueensFour: NQueensModel.spec
        case .diningPhilosophers: DiningPhilosophersModel.spec
        case .stringLiterals: StringLiteralModel.spec
        case .actionReferences: ActionReferencesModel.spec
        }
    }
}

package struct TLCReferenceArtifacts: Equatable, Sendable {
    package let jar: URL
    package let javaArchive: URL
    package let bridgeSources: [String: URL]
    package let bridgeBinary: URL
    package let jarManifest: String
    package let runtime: TLCJavaRuntimeIdentity

    package init(jar: URL, javaArchive: URL, bridgeSources: [String: URL], bridgeBinary: URL, jarManifest: String, runtime: TLCJavaRuntimeIdentity) {
        self.jar = jar
        self.javaArchive = javaArchive
        self.bridgeSources = bridgeSources
        self.bridgeBinary = bridgeBinary
        self.jarManifest = jarManifest
        self.runtime = runtime
    }
}

package struct TLCJavaRuntimeIdentity: Equatable, Sendable {
    package let version: String
    package let vendor: String
    package let architecture: String
    package let properties: [String: String]

    package init(version: String, vendor: String, architecture: String, properties: [String: String]) {
        self.version = version
        self.vendor = vendor
        self.architecture = architecture
        self.properties = properties
    }
}

package enum SHA256 {
    package static func hex(_ data: Data) -> String {
        CryptoKit.SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
