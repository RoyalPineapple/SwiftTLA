import CryptoKit
import Foundation

package enum CoreConformanceCaseError: Error, Equatable, Sendable {
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

package struct TLCReferencePin: Equatable, Sendable {
    package let tag: String
    package let commit: String
    package let jarSHA256: String
    package let javaDistribution: String
    package let javaVersion: String
    package let javaArchiveSHA256: String
    package let bridgeClass: String
    package let bridgeSourceSHA256: String
    package let bridgeBinarySHA256: String

    package init(
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
        guard !tag.isEmpty, Self.isRevision(commit) else {
            throw CoreConformanceCaseError.invalidIdentifier("TLC release")
        }
        guard !javaDistribution.isEmpty, !javaVersion.isEmpty else {
            throw CoreConformanceCaseError.invalidIdentifier("Java runtime")
        }
        guard !bridgeClass.isEmpty else {
            throw CoreConformanceCaseError.invalidIdentifier("bridge class")
        }
        for (field, value) in [
            ("jarSHA256", jarSHA256), ("javaArchiveSHA256", javaArchiveSHA256),
            ("bridgeSourceSHA256", bridgeSourceSHA256), ("bridgeBinarySHA256", bridgeBinarySHA256)
        ] where !Self.isSHA256(value) {
            throw CoreConformanceCaseError.invalidSHA256(field: field)
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
        else { throw CoreConformanceCaseError.pinMismatch("TLC JAR manifest") }
        guard artifacts.runtime.version == javaVersion,
              artifacts.runtime.vendor.contains("Eclipse Adoptium"),
              artifacts.runtime.properties["java.runtime.version"] == javaVersion,
              artifacts.runtime.properties["java.vendor"]?.contains("Eclipse Adoptium") == true
        else { throw CoreConformanceCaseError.pinMismatch("Java runtime") }
        guard !artifacts.runtime.architecture.isEmpty else {
            throw CoreConformanceCaseError.pinMismatch("Java architecture")
        }
        try Self.verify(artifacts.javaArchive, expected: javaArchiveSHA256, name: "Java archive")
        try Self.verify(artifacts.bridgeBinary, expected: bridgeBinarySHA256, name: "bridge binary")
        try Self.verify(artifacts.bridgeSource, expected: bridgeSourceSHA256, name: "bridge source")
    }

    package func validateReportedTLCBanner(_ output: String) throws {
        let revision = String(commit.prefix(7))
        guard output.split(whereSeparator: \.isNewline).contains(where: {
            $0.contains("TLC2 Version") && $0.contains("(rev: \(revision))")
        }) else {
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

    static func isRevision(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{40}$", options: .regularExpression) != nil
    }
}

package struct CoreConformanceCase: Equatable, Sendable {
    package let id: String
    package let moduleSHA256: String
    package let cfgSHA256: String
    package let arguments: [String]
    package let argumentsSHA256: String
    package let workers: Int
    package let fingerprintPolynomial: Int
    package let deadlock: Bool
    package let operatingSystem: String
    package let architecture: String
    package let environment: [String: String]
    package let pin: TLCReferencePin
    package let invocationMappings: [CoreConformanceInvocationMapping]
    package let valueNormalizations: [CoreConformanceValueNormalization]

    package init(
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
        invocationMappings: [CoreConformanceInvocationMapping] = [],
        valueNormalizations: [CoreConformanceValueNormalization] = []
    ) throws {
        guard !id.isEmpty else { throw CoreConformanceCaseError.invalidIdentifier("case ID") }
        guard TLCReferencePin.isSHA256(moduleSHA256) else { throw CoreConformanceCaseError.invalidSHA256(field: "moduleSHA256") }
        guard TLCReferencePin.isSHA256(cfgSHA256) else { throw CoreConformanceCaseError.invalidSHA256(field: "cfgSHA256") }
        guard workers == 1 else { throw CoreConformanceCaseError.invalidWorkers(workers) }
        guard fingerprintPolynomial >= 0 else { throw CoreConformanceCaseError.invalidFingerprintPolynomial(fingerprintPolynomial) }
        let computedArgumentsDigest = try Self.argumentsDigest(arguments)
        guard argumentsSHA256 == computedArgumentsDigest else { throw CoreConformanceCaseError.invalidArgumentsDigest }
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
        self.invocationMappings = invocationMappings
        self.valueNormalizations = valueNormalizations
    }

    package static func argumentsDigest(_ arguments: [String]) throws -> String {
        let encoded = try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        return SHA256.hex(encoded)
    }

    package func validateLaunch(module: URL, configuration: URL, arguments: [String], caseID: String) throws {
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

package struct CoreConformanceInvocationMapping: Equatable, Sendable {
    package let wrapper: String
    package let action: String
    package let arguments: [String]
    package let indices: [Int]

    package init(wrapper: String, action: String, arguments: [String], indices: [Int]) throws {
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

    package var swiftLabel: String {
        arguments.isEmpty ? action : "\(action)(\(arguments.joined(separator: ", ")))"
    }

    package var locationIdentity: String {
        tlaInvocationLocationIdentity(action: action, arguments: arguments)
    }
}

package struct CoreConformanceValueNormalization: Equatable, Sendable {
    package let binding: String
    package let functionKeys: [String: String]

    package init(binding: String, functionKeys: [String: String]) throws {
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
package struct CoreConformanceCasesManifest: Decodable, Sendable {
    package static let schema = "CoreConformanceCases"
    package static let relation = "exactFiniteTLCGraph"

    package let schema: String
    package let relation: String
    package let cases: [Entry]

    package struct Entry: Decodable, Sendable {
        package typealias IdentityMapping = CoreConformanceCaseManifestIdentityMapping
        package typealias InvocationMapping = CoreConformanceCaseManifestInvocationMapping
        package typealias ValueNormalization = CoreConformanceCaseManifestValueNormalization
        package typealias Upstream = CoreConformanceCaseManifestUpstream
        package typealias Fixtures = CoreConformanceCaseManifestFixtures
        package let id: String
        package let swiftSpec: String
        package let module: String
        package let configuration: String
        package let imports: [String]
        package let moduleSHA256: String
        package let cfgSHA256: String
        package let arguments: [String]
        package let argumentsSHA256: String
        package let workers: Int
        package let fingerprintPolynomial: Int
        package let maximumStateLimit: Int
        package let deadlock: Bool
        package let replay: String
        package let expectedExit: Int?
        package let upstream: Upstream
        package let fixtures: Fixtures
        package let identityMapping: IdentityMapping
        package let invocationMappings: [InvocationMapping]
        package let valueNormalizations: [ValueNormalization]

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, swiftSpec, module, configuration, imports, moduleSHA256, cfgSHA256
            case arguments, argumentsSHA256, workers, fingerprintPolynomial, maximumStateLimit, deadlock, replay
            case expectedExit, upstream, fixtures, identityMapping, invocationMappings, valueNormalizations
        }

        package init(from decoder: Decoder) throws {
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
            maximumStateLimit = try container.decode(Int.self, forKey: .maximumStateLimit)
            deadlock = try container.decode(Bool.self, forKey: .deadlock)
            replay = try container.decode(String.self, forKey: .replay)
            expectedExit = try container.decodeIfPresent(Int.self, forKey: .expectedExit)
            upstream = try container.decode(Upstream.self, forKey: .upstream)
            fixtures = try container.decode(Fixtures.self, forKey: .fixtures)
            identityMapping = try container.decode(IdentityMapping.self, forKey: .identityMapping)
            invocationMappings = try container.decodeIfPresent([InvocationMapping].self, forKey: .invocationMappings) ?? []
            valueNormalizations = try container.decodeIfPresent([ValueNormalization].self, forKey: .valueNormalizations) ?? []
            try validate()
        }

        package func validate() throws {
            guard !id.isEmpty, !swiftSpec.isEmpty, !module.isEmpty, !configuration.isEmpty,
                  Set(imports).count == imports.count, imports.allSatisfy({ !$0.isEmpty }),
                  !replay.isEmpty, !upstream.repository.isEmpty,
                  !upstream.commit.isEmpty, !fixtures.module.isEmpty, !fixtures.configuration.isEmpty else {
                throw ConformanceGovernanceError.invalidField(record: id, field: "case declaration")
            }
            let computedArgumentsDigest = try CoreConformanceCase.argumentsDigest(arguments)
            guard TLCReferencePin.isSHA256(moduleSHA256), TLCReferencePin.isSHA256(cfgSHA256),
                  argumentsSHA256 == computedArgumentsDigest, workers == 1,
                  fingerprintPolynomial >= 0, maximumStateLimit > 0 else {
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
            guard expectedExit == nil || expectedExit == 0 else {
                throw ConformanceGovernanceError.invalidField(record: id, field: "governance outcome")
            }
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case schema, relation, cases }

    package init(from decoder: Decoder) throws {
        let container = try ConformanceDecoding.container(decoder, keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        relation = try container.decode(String.self, forKey: .relation)
        cases = try container.decode([Entry].self, forKey: .cases)
        try validate()
    }

    package func validate() throws {
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

}

package struct TLCReferenceArtifacts: Equatable, Sendable {
    package let jar: URL
    package let javaArchive: URL
    package let bridgeSource: URL
    package let bridgeBinary: URL
    package let jarManifest: String
    package let runtime: TLCJavaRuntimeIdentity

    package init(jar: URL, javaArchive: URL, bridgeSource: URL, bridgeBinary: URL, jarManifest: String, runtime: TLCJavaRuntimeIdentity) {
        self.jar = jar
        self.javaArchive = javaArchive
        self.bridgeSource = bridgeSource
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
