import CryptoKit
import Foundation

public enum CoreConformanceCaseError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case invalidSHA256(field: String)
    case invalidWorkers(Int)
    case invalidFingerprintPolynomial(Int)
    case invalidArgumentsDigest
    case executionCaseMismatch
    case moduleDigestMismatch
    case cfgDigestMismatch
    case executionArgumentsMismatch
    case pinMismatch(String)
    case missingArtifact(String)
}

public struct TLCReferencePin: Equatable, Sendable {
    public let tag: String
    public let commit: String
    public let jarSHA256: String
    public let javaDistribution: String
    public let javaVersion: String
    public let javaArchiveSHA256: String
    public let bridgeClass: String
    public let bridgeSourceSHA256: String
    public let bridgeBinarySHA256: String

    public init(
        tag: String,
        commit: String,
        jarSHA256: String,
        javaDistribution: String,
        javaVersion: String,
        javaArchiveSHA256: String,
        bridgeClass: String,
        bridgeSourceSHA256: String,
        bridgeBinarySHA256: String
    ) throws {
        guard tag == "v1.8.0", commit == "0894c3407f4717fec7cc18bde3bf3c857fa47333" else {
            throw CoreConformanceCaseError.invalidIdentifier("TLC release")
        }
        guard javaDistribution == "Eclipse Temurin", javaVersion == "17.0.19+10" else {
            throw CoreConformanceCaseError.invalidIdentifier("Java runtime")
        }
        guard bridgeClass == "org.swifttla.conformance.LosslessStateWriter" else {
            throw CoreConformanceCaseError.invalidIdentifier("bridge class")
        }
        for (field, value) in [
            ("jarSHA256", jarSHA256), ("javaArchiveSHA256", javaArchiveSHA256),
            ("bridgeSourceSHA256", bridgeSourceSHA256), ("bridgeBinarySHA256", bridgeBinarySHA256)
        ] where !Self.isSHA256(value) {
            throw CoreConformanceCaseError.invalidSHA256(field: field)
        }
        guard jarSHA256 == Self.lockedJarSHA256 else {
            throw CoreConformanceCaseError.pinMismatch("TLC JAR digest")
        }
        guard Self.lockedJavaArchiveSHA256s.values.contains(javaArchiveSHA256) else {
            throw CoreConformanceCaseError.pinMismatch("Java archive digest")
        }
        guard bridgeSourceSHA256 == Self.lockedBridgeSourceSHA256 else {
            throw CoreConformanceCaseError.pinMismatch("bridge source digest")
        }
        guard bridgeBinarySHA256 == Self.lockedBridgeBinarySHA256 else {
            throw CoreConformanceCaseError.pinMismatch("bridge binary digest")
        }
        self.tag = tag
        self.commit = commit
        self.jarSHA256 = jarSHA256
        self.javaDistribution = javaDistribution
        self.javaVersion = javaVersion
        self.javaArchiveSHA256 = javaArchiveSHA256
        self.bridgeClass = bridgeClass
        self.bridgeSourceSHA256 = bridgeSourceSHA256
        self.bridgeBinarySHA256 = bridgeBinarySHA256
    }

    public static let fixture = Self()

    private init() {
        tag = "v1.8.0"
        commit = "0894c3407f4717fec7cc18bde3bf3c857fa47333"
        jarSHA256 = "ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f"
        javaDistribution = "Eclipse Temurin"
        javaVersion = "17.0.19+10"
        javaArchiveSHA256 = "8fa1eff40bb637a33613b2ccb8b12c70dc3661cc22cf8e784943715769a05336"
        bridgeClass = "org.swifttla.conformance.LosslessStateWriter"
        bridgeSourceSHA256 = "f921b202205dde3d34e626f7801676cc0635de58f503c3dddd3affcc893532ee"
        bridgeBinarySHA256 = "a50ae51e9c540a3c0eb9386b05bb0c0f677cefa62bcfdc48545c6046ccb12d64"
    }

    public static let lockedJarSHA256 = "ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f"
    public static let lockedJavaArchiveSHA256s = [
        "arm64": "8fa1eff40bb637a33613b2ccb8b12c70dc3661cc22cf8e784943715769a05336",
        "x86_64": "03632d1fbf139ab3719a9f4b47dc206251449b87557143c822336dbf8c06560f"
    ]
    public static let lockedBridgeSourceSHA256 = "f921b202205dde3d34e626f7801676cc0635de58f503c3dddd3affcc893532ee"
    public static let lockedBridgeBinarySHA256 = "a50ae51e9c540a3c0eb9386b05bb0c0f677cefa62bcfdc48545c6046ccb12d64"
    public static let lockedTLCBanner = "TLC2 Version 2026.08.11.125311 (rev: 0894c34)"
    public static let standardModuleNames: Set<String> = [
        "Bags", "FiniteSets", "Integers", "Json", "Naturals", "Randomization", "RealTime",
        "Reals", "Sequences", "TLC", "TLCExt", "Toolbox", "_DotTrace", "_JsonTrace",
        "_Possible", "_TLAPlusCounterExample", "_TLCActionTrace", "_TLCTESpec", "_TLCTrace",
        "_TLCTracePlain"
    ]


    public func validate(_ artifacts: TLCReferenceArtifacts) throws {
        try Self.verify(artifacts.jar, expected: jarSHA256, name: "TLC JAR")
        guard artifacts.jarManifest.contains("Implementation-Title: TLA+ Tools"),
              artifacts.jarManifest.contains("X-Git-Revision: 0894c3407f4717fec7cc18bde3bf3c857fa47333")
        else { throw CoreConformanceCaseError.pinMismatch("TLC JAR manifest") }
        guard artifacts.runtime.version == javaVersion,
              artifacts.runtime.vendor.contains("Eclipse Adoptium"),
              artifacts.runtime.properties["java.runtime.version"] == javaVersion,
              artifacts.runtime.properties["java.vendor"]?.contains("Eclipse Adoptium") == true
        else { throw CoreConformanceCaseError.pinMismatch("Java runtime") }
        guard let expectedArchive = Self.lockedJavaArchiveSHA256s[artifacts.runtime.architecture],
              expectedArchive == javaArchiveSHA256
        else { throw CoreConformanceCaseError.pinMismatch("Java architecture") }
        try Self.verify(artifacts.javaArchive, expected: javaArchiveSHA256, name: "Java archive")
        try Self.verify(artifacts.bridgeBinary, expected: bridgeBinarySHA256, name: "bridge binary")
        try Self.verify(artifacts.bridgeSource, expected: bridgeSourceSHA256, name: "bridge source")
    }

    public func validateReportedTLCBanner(_ output: String) throws {
        guard output.split(whereSeparator: \.isNewline).contains(Substring(Self.lockedTLCBanner)) else {
            throw CoreConformanceCaseError.pinMismatch("TLC banner")
        }
    }

    private static func verify(_ file: URL, expected: String, name: String) throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw CoreConformanceCaseError.missingArtifact(name)
        }
        guard SHA256.hex(try Data(contentsOf: file)) == expected else {
            throw CoreConformanceCaseError.pinMismatch(name)
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}

public struct CoreConformanceCase: Equatable, Sendable {
    public let id: String
    public let moduleSHA256: String
    public let cfgSHA256: String
    public let arguments: [String]
    public let argumentsSHA256: String
    public let workers: Int
    public let fingerprintPolynomial: Int
    public let deadlock: Bool
    public let operatingSystem: String
    public let architecture: String
    public let environment: [String: String]
    public let pin: TLCReferencePin
    public let governance: CoreConformanceCaseGovernance?
    public let invocationMappings: [CoreConformanceInvocationMapping]
    public let valueNormalizations: [CoreConformanceValueNormalization]

    public init(
        id: String,
        moduleSHA256: String,
        cfgSHA256: String,
        arguments: [String],
        argumentsSHA256: String,
        workers: Int,
        fingerprintPolynomial: Int,
        deadlock: Bool,
        operatingSystem: String,
        architecture: String,
        environment: [String: String],
        pin: TLCReferencePin,
        governance: CoreConformanceCaseGovernance? = nil,
        invocationMappings: [CoreConformanceInvocationMapping] = [],
        valueNormalizations: [CoreConformanceValueNormalization] = []
    ) throws {
        guard !id.isEmpty else { throw CoreConformanceCaseError.invalidIdentifier("case ID") }
        guard TLCReferencePin.isSHA256(moduleSHA256) else { throw CoreConformanceCaseError.invalidSHA256(field: "moduleSHA256") }
        guard TLCReferencePin.isSHA256(cfgSHA256) else { throw CoreConformanceCaseError.invalidSHA256(field: "cfgSHA256") }
        guard workers == 1 else { throw CoreConformanceCaseError.invalidWorkers(workers) }
        guard fingerprintPolynomial >= 0 else { throw CoreConformanceCaseError.invalidFingerprintPolynomial(fingerprintPolynomial) }
        guard argumentsSHA256 == try Self.argumentsDigest(arguments) else { throw CoreConformanceCaseError.invalidArgumentsDigest }
        self.id = id
        self.moduleSHA256 = moduleSHA256
        self.cfgSHA256 = cfgSHA256
        self.arguments = arguments
        self.argumentsSHA256 = argumentsSHA256
        self.workers = workers
        self.fingerprintPolynomial = fingerprintPolynomial
        self.deadlock = deadlock
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.environment = environment
        self.pin = pin
        self.governance = governance
        self.invocationMappings = invocationMappings
        self.valueNormalizations = valueNormalizations
    }

    public static func argumentsDigest(_ arguments: [String]) throws -> String {
        let encoded = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        return SHA256.hex(encoded)
    }

    public func validateLaunch(module: URL, configuration: URL, arguments: [String], caseID: String) throws {
        guard caseID == id else { throw CoreConformanceCaseError.executionCaseMismatch }
        guard SHA256.hex(try Data(contentsOf: module)) == moduleSHA256 else {
            throw CoreConformanceCaseError.moduleDigestMismatch
        }
        guard SHA256.hex(try Data(contentsOf: configuration)) == cfgSHA256 else {
            throw CoreConformanceCaseError.cfgDigestMismatch
        }
        guard arguments == self.arguments, try Self.argumentsDigest(arguments) == argumentsSHA256 else {
            throw CoreConformanceCaseError.executionArgumentsMismatch
        }
    }
}

public struct CoreConformanceInvocationMapping: Equatable, Sendable {
    public let wrapper: String
    public let action: String
    public let arguments: [String]
    public let indices: [Int]

    public init(wrapper: String, action: String, arguments: [String], indices: [Int]) throws {
        guard !wrapper.isEmpty, !action.isEmpty,
              !arguments.contains(where: \.isEmpty),
              indices.count == arguments.count,
              indices.allSatisfy({ $0 >= 0 }) else {
            throw CoreConformanceCaseError.invalidIdentifier("invocation mapping")
        }
        self.wrapper = wrapper
        self.action = action
        self.arguments = arguments
        self.indices = indices
    }

    public var swiftLabel: String {
        arguments.isEmpty ? action : "\(action)(\(arguments.joined(separator: ", ")))"
    }

    public var locationIdentity: String {
        tlaInvocationLocationIdentity(action: action, arguments: arguments)
    }
}

public struct CoreConformanceValueNormalization: Equatable, Sendable {
    public let binding: String
    public let functionKeys: [String: String]

    public init(binding: String, functionKeys: [String: String]) throws {
        guard !binding.isEmpty,
              !functionKeys.isEmpty,
              !functionKeys.keys.contains(where: \.isEmpty),
              !functionKeys.values.contains(where: \.isEmpty),
              Set(functionKeys.values).count == functionKeys.count else {
            throw CoreConformanceCaseError.invalidIdentifier("value normalization")
        }
        self.binding = binding
        self.functionKeys = functionKeys
    }
}

func tlaInvocationLocationIdentity(action: String, arguments: [String]) -> String {
    "\(action)(\(arguments.map(tlaLocationArgumentIdentity).joined(separator: ",")))"
}

func tlaLocationArgumentIdentity(_ argument: String) -> String {
    var result = String()
    var quoted = false
    var escaped = false
    for character in argument.trimmingCharacters(in: .whitespacesAndNewlines) {
        if quoted {
            result.append(character)
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted = false
            }
        } else if character == "\"" {
            quoted = true
            result.append(character)
        } else if !character.isWhitespace {
            result.append(character)
        }
    }
    return result
}

/// The source-controlled declaration for a finite conformance case.
///
/// This is deliberately separate from `CoreConformanceCase`: the latter is
/// the runtime launch contract, while this type retains the governance facts
/// that make a launch eligible for support evidence.
public struct CoreConformanceCasesManifest: Decodable, Sendable {
    public static let schema = "CoreConformanceCases"
    public static let relation = "exactFiniteTLCGraph"

    public let schema: String
    public let relation: String
    public let cases: [Entry]

    public struct Entry: Decodable, Sendable {
        public typealias IdentityMapping = CoreConformanceCaseManifestIdentityMapping
        public typealias InvocationMapping = CoreConformanceCaseManifestInvocationMapping
        public typealias ValueNormalization = CoreConformanceCaseManifestValueNormalization
        public typealias Upstream = CoreConformanceCaseManifestUpstream
        public typealias Fixtures = CoreConformanceCaseManifestFixtures
        public let id: String
        public let swiftSpec: String
        public let module: String
        public let configuration: String
        public let imports: [String]
        public let moduleSHA256: String
        public let cfgSHA256: String
        public let arguments: [String]
        public let argumentsSHA256: String
        public let workers: Int
        public let fingerprintPolynomial: Int
        public let deadlock: Bool
        public let replay: String
        public let expectedExit: Int?
        public let upstream: Upstream
        public let fixtures: Fixtures
        public let identityMapping: IdentityMapping
        public let invocationMappings: [InvocationMapping]
        public let valueNormalizations: [ValueNormalization]
        public let semanticCitations: [String]
        public let governance: CoreConformanceCaseGovernance
        public let expectedArtifacts: String

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, swiftSpec, module, configuration, imports, moduleSHA256, cfgSHA256
            case arguments, argumentsSHA256, workers, fingerprintPolynomial, deadlock, replay
            case expectedExit, upstream, fixtures, identityMapping, invocationMappings, valueNormalizations, semanticCitations, governance
            case expectedArtifacts
        }

        public init(from decoder: Decoder) throws {
            let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            swiftSpec = try container.decode(String.self, forKey: .swiftSpec)
            module = try container.decode(String.self, forKey: .module)
            configuration = try container.decode(String.self, forKey: .configuration)
            imports = try container.decode([String].self, forKey: .imports)
            moduleSHA256 = try container.decode(String.self, forKey: .moduleSHA256)
            cfgSHA256 = try container.decode(String.self, forKey: .cfgSHA256)
            arguments = try container.decode([String].self, forKey: .arguments)
            argumentsSHA256 = try container.decode(String.self, forKey: .argumentsSHA256)
            workers = try container.decode(Int.self, forKey: .workers)
            fingerprintPolynomial = try container.decode(Int.self, forKey: .fingerprintPolynomial)
            deadlock = try container.decode(Bool.self, forKey: .deadlock)
            replay = try container.decode(String.self, forKey: .replay)
            expectedExit = try container.decodeIfPresent(Int.self, forKey: .expectedExit)
            upstream = try container.decode(Upstream.self, forKey: .upstream)
            fixtures = try container.decode(Fixtures.self, forKey: .fixtures)
            identityMapping = try container.decode(IdentityMapping.self, forKey: .identityMapping)
            invocationMappings = try container.decodeIfPresent([InvocationMapping].self, forKey: .invocationMappings) ?? []
            valueNormalizations = try container.decodeIfPresent([ValueNormalization].self, forKey: .valueNormalizations) ?? []
            semanticCitations = try container.decode([String].self, forKey: .semanticCitations)
            governance = try container.decode(CoreConformanceCaseGovernance.self, forKey: .governance)
            expectedArtifacts = try container.decode(String.self, forKey: .expectedArtifacts)
            try validate()
        }

        public func validate() throws {
            guard !id.isEmpty, !swiftSpec.isEmpty, !module.isEmpty, !configuration.isEmpty,
                  Set(imports).count == imports.count, imports.allSatisfy({ !$0.isEmpty }),
                  !replay.isEmpty, !expectedArtifacts.isEmpty, !upstream.repository.isEmpty,
                  !upstream.commit.isEmpty, !fixtures.module.isEmpty, !fixtures.configuration.isEmpty,
                  !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }) else {
                throw ConformanceGovernanceError.invalidField(record: id, field: "case declaration")
            }
            guard TLCReferencePin.isSHA256(moduleSHA256), TLCReferencePin.isSHA256(cfgSHA256),
                  argumentsSHA256 == try CoreConformanceCase.argumentsDigest(arguments), workers == 1,
                  fingerprintPolynomial >= 0 else {
                throw ConformanceGovernanceError.invalidField(record: id, field: "launch contract")
            }
            let wrappers = invocationMappings.map(\.wrapper)
            let labels = try invocationMappings.map { try $0.runtimeValue().swiftLabel }
            let locations = try invocationMappings.map { try $0.runtimeValue().locationIdentity }
            let normalizedBindings = valueNormalizations.map(\.binding)
            guard Set(wrappers).count == wrappers.count,
                  Set(labels).count == labels.count,
                  Set(locations).count == locations.count,
                  Set(normalizedBindings).count == normalizedBindings.count else {
                throw ConformanceGovernanceError.invalidField(record: id, field: "invocationMappings")
            }
            let expectedOutcome: CoreRegressionOutcome = expectedExit == nil || expectedExit == 0
                ? .exact : .difference
            guard expectedExit == nil || expectedExit == 0 || expectedExit == 1,
                  governance.expectedRegressionOutcome == expectedOutcome,
                  (governance.role == .requiredComparison) == (expectedOutcome == .exact) else {
                throw ConformanceGovernanceError.invalidField(record: id, field: "governance outcome")
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, relation, cases }

    public init(from decoder: Decoder) throws {
        let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        relation = try container.decode(String.self, forKey: .relation)
        cases = try container.decode([Entry].self, forKey: .cases)
        try validate()
    }

    public func validate() throws {
        guard schema == Self.schema, relation == Self.relation, !cases.isEmpty else {
            throw ConformanceGovernanceError.invalidSchema(schema)
        }
        var ids = Set<String>()
        for entry in cases {
            try entry.validate()
            guard ids.insert(entry.id).inserted else {
                throw ConformanceGovernanceError.duplicateID(kind: "case", id: entry.id)
            }
        }
    }

    public func validate(ledger: CoreDivergenceLedger) throws {
        try validate()
        let entries = Dictionary(uniqueKeysWithValues: cases.map { ($0.id, $0) })
        try ledger.validate(caseIDs: Set(entries.keys))
        for record in ledger.records {
            guard let original = entries[record.provenance.caseID],
                  let regression = entries[record.permanentRegressionCaseID],
                  regression.governance.role == .permanentRegression,
                  regression.governance.expectedRegressionOutcome == .difference,
                  original.moduleSHA256 == record.provenance.moduleSHA256,
                  original.cfgSHA256 == record.provenance.cfgSHA256,
                  original.argumentsSHA256 == record.provenance.argumentsSHA256,
                  Set(record.semanticCitations).isSubset(of: Set(original.governance.semanticCitations)) else {
                throw ConformanceGovernanceError.invalidField(record: record.id, field: "case governance correlation")
            }
            guard record.provenance.tlcTag == TLCReferencePin.fixture.tag,
                  record.provenance.tlcCommit == TLCReferencePin.fixture.commit,
                  record.provenance.tlcJarSHA256 == TLCReferencePin.fixture.jarSHA256,
                  record.provenance.javaDistribution == TLCReferencePin.fixture.javaDistribution,
                  record.provenance.javaVersion == TLCReferencePin.fixture.javaVersion,
                  record.provenance.javaArchiveSHA256 == TLCReferencePin.fixture.javaArchiveSHA256,
                  record.provenance.bridgeClass == TLCReferencePin.fixture.bridgeClass,
                  record.provenance.bridgeSourceSHA256 == TLCReferencePin.fixture.bridgeSourceSHA256,
                  record.provenance.bridgeBinarySHA256 == TLCReferencePin.fixture.bridgeBinarySHA256 else {
                throw ConformanceGovernanceError.invalidField(record: record.id, field: "TLC reference pin")
            }
        }
    }
}

public struct TLCReferenceArtifacts: Equatable, Sendable {
    public let jar: URL
    public let javaArchive: URL
    public let bridgeSource: URL
    public let bridgeBinary: URL
    public let jarManifest: String
    public let runtime: TLCJavaRuntimeIdentity

    public init(jar: URL, javaArchive: URL, bridgeSource: URL, bridgeBinary: URL, jarManifest: String, runtime: TLCJavaRuntimeIdentity) {
        self.jar = jar
        self.javaArchive = javaArchive
        self.bridgeSource = bridgeSource
        self.bridgeBinary = bridgeBinary
        self.jarManifest = jarManifest
        self.runtime = runtime
    }
}

public struct TLCJavaRuntimeIdentity: Equatable, Sendable {
    public let version: String
    public let vendor: String
    public let architecture: String
    public let properties: [String: String]

    public init(version: String, vendor: String, architecture: String, properties: [String: String]) {
        self.version = version
        self.vendor = vendor
        self.architecture = architecture
        self.properties = properties
    }
}

public enum SHA256 {
    public static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
