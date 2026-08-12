import CryptoKit
import Foundation

public enum CoreConformanceCaseErrorV1: Error, Equatable, Sendable {
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

public struct TLCReferencePinV1: Equatable, Sendable {
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
        guard tag == "v1.8.0", commit == "30cc3601321c3fc02e044d0ecb5c58d8921e18df" else {
            throw CoreConformanceCaseErrorV1.invalidIdentifier("TLC release")
        }
        guard javaDistribution == "Eclipse Temurin", javaVersion == "17.0.19+10" else {
            throw CoreConformanceCaseErrorV1.invalidIdentifier("Java runtime")
        }
        guard bridgeClass == "org.swifttla.conformance.LosslessStateWriter" else {
            throw CoreConformanceCaseErrorV1.invalidIdentifier("bridge class")
        }
        for (field, value) in [
            ("jarSHA256", jarSHA256), ("javaArchiveSHA256", javaArchiveSHA256),
            ("bridgeSourceSHA256", bridgeSourceSHA256), ("bridgeBinarySHA256", bridgeBinarySHA256)
        ] where !Self.isSHA256(value) {
            throw CoreConformanceCaseErrorV1.invalidSHA256(field: field)
        }
        guard jarSHA256 == Self.lockedJarSHA256 else {
            throw CoreConformanceCaseErrorV1.pinMismatch("TLC JAR digest")
        }
        guard Self.lockedJavaArchiveSHA256s.values.contains(javaArchiveSHA256) else {
            throw CoreConformanceCaseErrorV1.pinMismatch("Java archive digest")
        }
        guard bridgeSourceSHA256 == Self.lockedBridgeSourceSHA256 else {
            throw CoreConformanceCaseErrorV1.pinMismatch("bridge source digest")
        }
        guard bridgeBinarySHA256 == Self.lockedBridgeBinarySHA256 else {
            throw CoreConformanceCaseErrorV1.pinMismatch("bridge binary digest")
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

    public static let fixture = try! Self(
        tag: "v1.8.0",
        commit: "30cc3601321c3fc02e044d0ecb5c58d8921e18df",
        jarSHA256: "e22f8ffb4bacdea0a871f444dd94fe5fb0d8013b3388ae39e82e26f852c735d5",
        javaDistribution: "Eclipse Temurin",
        javaVersion: "17.0.19+10",
        javaArchiveSHA256: "8fa1eff40bb637a33613b2ccb8b12c70dc3661cc22cf8e784943715769a05336",
        bridgeClass: "org.swifttla.conformance.LosslessStateWriter",
        bridgeSourceSHA256: "f921b202205dde3d34e626f7801676cc0635de58f503c3dddd3affcc893532ee",
        bridgeBinarySHA256: "a50ae51e9c540a3c0eb9386b05bb0c0f677cefa62bcfdc48545c6046ccb12d64"
    )

    public static let lockedJarSHA256 = "e22f8ffb4bacdea0a871f444dd94fe5fb0d8013b3388ae39e82e26f852c735d5"
    public static let lockedJavaArchiveSHA256s = [
        "arm64": "8fa1eff40bb637a33613b2ccb8b12c70dc3661cc22cf8e784943715769a05336",
        "x86_64": "03632d1fbf139ab3719a9f4b47dc206251449b87557143c822336dbf8c06560f"
    ]
    public static let lockedBridgeSourceSHA256 = "f921b202205dde3d34e626f7801676cc0635de58f503c3dddd3affcc893532ee"
    public static let lockedBridgeBinarySHA256 = "a50ae51e9c540a3c0eb9386b05bb0c0f677cefa62bcfdc48545c6046ccb12d64"
    public static let lockedTLCBanner = "TLC2 Version 2026.07.31.184830 (rev: 30cc360)"

    public func validate(_ artifacts: TLCReferenceArtifactsV1) throws {
        try Self.verify(artifacts.jar, expected: jarSHA256, name: "TLC JAR")
        guard artifacts.jarManifest.contains("X-Git-Tag: ") && artifacts.jarManifest.contains("v1.8.0"),
              artifacts.jarManifest.contains("X-Git-Revision: 30cc3601321c3fc02e044d0ecb5c58d8921e18df")
        else { throw CoreConformanceCaseErrorV1.pinMismatch("TLC JAR manifest") }
        guard artifacts.runtime.version == javaVersion,
              artifacts.runtime.vendor.contains("Eclipse Adoptium"),
              artifacts.runtime.properties["java.runtime.version"] == javaVersion,
              artifacts.runtime.properties["java.vendor"]?.contains("Eclipse Adoptium") == true
        else { throw CoreConformanceCaseErrorV1.pinMismatch("Java runtime") }
        guard let expectedArchive = Self.lockedJavaArchiveSHA256s[artifacts.runtime.architecture],
              expectedArchive == javaArchiveSHA256
        else { throw CoreConformanceCaseErrorV1.pinMismatch("Java architecture") }
        try Self.verify(artifacts.javaArchive, expected: javaArchiveSHA256, name: "Java archive")
        try Self.verify(artifacts.bridgeBinary, expected: bridgeBinarySHA256, name: "bridge binary")
        try Self.verify(artifacts.bridgeSource, expected: bridgeSourceSHA256, name: "bridge source")
    }

    public func validateReportedTLCBanner(_ output: String) throws {
        guard output.split(whereSeparator: \.isNewline).contains(Substring(Self.lockedTLCBanner)) else {
            throw CoreConformanceCaseErrorV1.pinMismatch("TLC banner")
        }
    }

    private static func verify(_ file: URL, expected: String, name: String) throws {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw CoreConformanceCaseErrorV1.missingArtifact(name)
        }
        guard SHA256V1.hex(try Data(contentsOf: file)) == expected else {
            throw CoreConformanceCaseErrorV1.pinMismatch(name)
        }
    }

    static func isSHA256(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}

public struct CoreConformanceCaseV1: Equatable, Sendable {
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
    public let pin: TLCReferencePinV1
    public let governance: CoreConformanceCaseGovernanceV1?

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
        pin: TLCReferencePinV1,
        governance: CoreConformanceCaseGovernanceV1? = nil
    ) throws {
        guard !id.isEmpty else { throw CoreConformanceCaseErrorV1.invalidIdentifier("case ID") }
        guard TLCReferencePinV1.isSHA256(moduleSHA256) else { throw CoreConformanceCaseErrorV1.invalidSHA256(field: "moduleSHA256") }
        guard TLCReferencePinV1.isSHA256(cfgSHA256) else { throw CoreConformanceCaseErrorV1.invalidSHA256(field: "cfgSHA256") }
        guard workers == 1 else { throw CoreConformanceCaseErrorV1.invalidWorkers(workers) }
        guard fingerprintPolynomial >= 0 else { throw CoreConformanceCaseErrorV1.invalidFingerprintPolynomial(fingerprintPolynomial) }
        guard argumentsSHA256 == Self.argumentsDigest(arguments) else { throw CoreConformanceCaseErrorV1.invalidArgumentsDigest }
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
    }

    public static func argumentsDigest(_ arguments: [String]) -> String {
        let encoded = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        return SHA256V1.hex(encoded)
    }

    public func validateLaunch(module: URL, configuration: URL, arguments: [String], caseID: String) throws {
        guard caseID == id else { throw CoreConformanceCaseErrorV1.executionCaseMismatch }
        guard SHA256V1.hex(try Data(contentsOf: module)) == moduleSHA256 else {
            throw CoreConformanceCaseErrorV1.moduleDigestMismatch
        }
        guard SHA256V1.hex(try Data(contentsOf: configuration)) == cfgSHA256 else {
            throw CoreConformanceCaseErrorV1.cfgDigestMismatch
        }
        guard arguments == self.arguments, Self.argumentsDigest(arguments) == argumentsSHA256 else {
            throw CoreConformanceCaseErrorV1.executionArgumentsMismatch
        }
    }
}

/// The source-controlled declaration for a finite conformance case.
///
/// This is deliberately separate from `CoreConformanceCaseV1`: the latter is
/// the runtime launch contract, while this type retains the governance facts
/// that make a launch eligible for support evidence.
public struct CoreConformanceCasesManifestV1: Decodable, Sendable {
    public static let schema = "CoreConformanceCasesV1"
    public static let relation = "exactFiniteTLCGraphV1"

    public let schema: String
    public let relation: String
    public let cases: [Entry]

    public struct Entry: Decodable, Sendable {
        public struct IdentityMapping: Decodable, Sendable {
            public let variables: [String: String]
            public let actions: [String: String]

            private enum CodingKeys: String, CodingKey, CaseIterable { case variables, actions }

            public init(from decoder: Decoder) throws {
                let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
                variables = try container.decode([String: String].self, forKey: .variables)
                actions = try container.decode([String: String].self, forKey: .actions)
            }
        }

        public struct Upstream: Decodable, Sendable {
            public let repository: String
            public let commit: String

            private enum CodingKeys: String, CodingKey, CaseIterable { case repository, commit }

            public init(from decoder: Decoder) throws {
                let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
                repository = try container.decode(String.self, forKey: .repository)
                commit = try container.decode(String.self, forKey: .commit)
            }
        }

        public struct Fixtures: Decodable, Sendable {
            public let module: String
            public let configuration: String

            private enum CodingKeys: String, CodingKey, CaseIterable { case module, configuration }

            public init(from decoder: Decoder) throws {
                let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
                module = try container.decode(String.self, forKey: .module)
                configuration = try container.decode(String.self, forKey: .configuration)
            }
        }

        public let id: String
        public let swiftSpec: String
        public let module: String
        public let configuration: String
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
        public let semanticCitations: [String]
        public let governance: CoreConformanceCaseGovernanceV1
        public let expectedArtifacts: String

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, swiftSpec, module, configuration, moduleSHA256, cfgSHA256
            case arguments, argumentsSHA256, workers, fingerprintPolynomial, deadlock, replay
            case expectedExit, upstream, fixtures, identityMapping, semanticCitations, governance
            case expectedArtifacts
        }

        public init(from decoder: Decoder) throws {
            let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            swiftSpec = try container.decode(String.self, forKey: .swiftSpec)
            module = try container.decode(String.self, forKey: .module)
            configuration = try container.decode(String.self, forKey: .configuration)
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
            semanticCitations = try container.decode([String].self, forKey: .semanticCitations)
            governance = try container.decode(CoreConformanceCaseGovernanceV1.self, forKey: .governance)
            expectedArtifacts = try container.decode(String.self, forKey: .expectedArtifacts)
            try validate()
        }

        public func validate() throws {
            guard !id.isEmpty, !swiftSpec.isEmpty, !module.isEmpty, !configuration.isEmpty,
                  !replay.isEmpty, !expectedArtifacts.isEmpty, !upstream.repository.isEmpty,
                  !upstream.commit.isEmpty, !fixtures.module.isEmpty, !fixtures.configuration.isEmpty,
                  !semanticCitations.isEmpty, semanticCitations.allSatisfy({ !$0.isEmpty }) else {
                throw CoreGovernanceErrorV1.invalidField(record: id, field: "case declaration")
            }
            guard TLCReferencePinV1.isSHA256(moduleSHA256), TLCReferencePinV1.isSHA256(cfgSHA256),
                  argumentsSHA256 == CoreConformanceCaseV1.argumentsDigest(arguments), workers == 1,
                  fingerprintPolynomial >= 0 else {
                throw CoreGovernanceErrorV1.invalidField(record: id, field: "launch contract")
            }
            let expectedOutcome: CoreRegressionOutcomeV1 = expectedExit == nil || expectedExit == 0
                ? .exact : .difference
            guard expectedExit == nil || expectedExit == 0 || expectedExit == 1,
                  governance.expectedRegressionOutcome == expectedOutcome,
                  (governance.role == .requiredComparison) == (expectedOutcome == .exact) else {
                throw CoreGovernanceErrorV1.invalidField(record: id, field: "governance outcome")
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, relation, cases }

    public init(from decoder: Decoder) throws {
        let container = try CoreGovernanceDecodingV1.container(decoder, keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        relation = try container.decode(String.self, forKey: .relation)
        cases = try container.decode([Entry].self, forKey: .cases)
        try validate()
    }

    public func validate() throws {
        guard schema == Self.schema, relation == Self.relation, !cases.isEmpty else {
            throw CoreGovernanceErrorV1.invalidSchema(schema)
        }
        var ids = Set<String>()
        for entry in cases {
            try entry.validate()
            guard ids.insert(entry.id).inserted else {
                throw CoreGovernanceErrorV1.duplicateID(kind: "case", id: entry.id)
            }
        }
    }

    public func validate(ledger: CoreDivergenceLedgerV1) throws {
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
                throw CoreGovernanceErrorV1.invalidField(record: record.id, field: "case governance correlation")
            }
        }
    }
}

public struct TLCReferenceArtifactsV1: Equatable, Sendable {
    public let jar: URL
    public let javaArchive: URL
    public let bridgeSource: URL
    public let bridgeBinary: URL
    public let jarManifest: String
    public let runtime: TLCJavaRuntimeIdentityV1

    public init(jar: URL, javaArchive: URL, bridgeSource: URL, bridgeBinary: URL, jarManifest: String, runtime: TLCJavaRuntimeIdentityV1) {
        self.jar = jar
        self.javaArchive = javaArchive
        self.bridgeSource = bridgeSource
        self.bridgeBinary = bridgeBinary
        self.jarManifest = jarManifest
        self.runtime = runtime
    }
}

public struct TLCJavaRuntimeIdentityV1: Equatable, Sendable {
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

public enum SHA256V1 {
    public static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
