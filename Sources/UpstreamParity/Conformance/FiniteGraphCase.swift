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
            ("bridgeSourceSHA256", bridgeSourceSHA256), ("bridgeBinarySHA256", bridgeBinarySHA256)
        ] where !Self.isSHA256(value) {
            throw FiniteGraphCaseError.invalidSHA256(field: field)
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
        try Self.verify(artifacts.bridgeSource, expected: bridgeSourceSHA256, name: "bridge source")
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
package struct FiniteGraphManifest: Decodable, Sendable {
    package static let schema = "FiniteGraphCases"

    package let schema: String
    package let cases: [Case]

    package struct Case: Decodable, Sendable {
        package let id: String
        package let module: String
        package let configuration: String
        package let imports: [String]
        package let moduleSHA256: String
        package let cfgSHA256: String
        package let exploration: FiniteExplorationConfiguration

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case id, module, configuration, imports, moduleSHA256, cfgSHA256, exploration
        }

        package init(from decoder: Decoder) throws {
            let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            module = try container.decode(String.self, forKey: .module)
            configuration = try container.decode(String.self, forKey: .configuration)
            imports = try container.decode([String].self, forKey: .imports)
            moduleSHA256 = try container.decode(String.self, forKey: .moduleSHA256)
            cfgSHA256 = try container.decode(String.self, forKey: .cfgSHA256)
            exploration = try container.decode(
                FiniteExplorationConfiguration.self,
                forKey: .exploration
            )
            try validate()
        }

        package func validate() throws {
            guard !id.isEmpty, !module.isEmpty, !configuration.isEmpty,
                  Set(imports).count == imports.count, imports.allSatisfy({ !$0.isEmpty }) else {
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
        let container = try StrictEvidenceDecoding.container(decoder, keyedBy: CodingKeys.self)
        schema = try container.decode(String.self, forKey: .schema)
        cases = try container.decode([Case].self, forKey: .cases)
        try validate()
    }

    package func validate() throws {
        guard schema == Self.schema, !cases.isEmpty else {
            throw EvidenceFormatError.invalidSchema(schema)
        }
        var ids = Set<String>()
        for finiteGraphCase in cases {
            try finiteGraphCase.validate()
            guard ids.insert(finiteGraphCase.id).inserted else {
                throw EvidenceFormatError.duplicateID(kind: "case", id: finiteGraphCase.id)
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
