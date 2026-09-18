import CryptoKit
import Foundation
import Testing
@testable import UpstreamParity

struct UpstreamCorpusInventoryTests {
    private struct Coverage: Decodable {
        struct Implementation: Decodable {
            let file: String
            let scenario: String
            let caseID: String
        }
        struct Evidence: Decodable {
            let sourceSHA: String
            let developerToolsVersion: String
            let runURL: String
            let artifactURL: String
            let completeGraph: Bool?
            let allPropertiesMatch: Bool?
            let acceptanceComplete: Bool?
            let environment: [String: String]?

            func matches(sourceSHA: String, developerToolsVersion: String, environment: [String: String]?) -> Bool {
                self.sourceSHA == sourceSHA
                    && self.developerToolsVersion == developerToolsVersion
                    && self.environment == environment
            }
        }
        struct Configuration: Decodable {
            struct Variant: Decodable {
                let environment: [String: String]
                let status: String
                let implementations: [Implementation]
                let evidence: [Evidence]
            }
            let module: String
            let configuration: String
            let required: Bool
            let status: String
            let implementations: [Implementation]
            let evidence: [Evidence]
            let environmentVariants: [Variant]?
            let variantAuditComplete: Bool?
            let variantReason: String?
        }
        struct Module: Decodable {
            let path: String
            let reason: String
        }
        struct Family: Decodable {
            let path: String
            let modules: [Module]
            let configurations: [Configuration]
        }
        struct Criterion: Decodable {
            let id: String
            let status: String
            let evidence: [Evidence]
        }
        struct CI: Decodable {
            let hostedXcode: String
        }
        let upstreamRevision: String
        let auditedSwiftSHA: String
        let ci: CI
        let families: [Family]
        let dslCriteria: [Criterion]
    }

    private struct Inventory: Decodable {
        struct File: Decodable {
            let path: String
            let gitBlobSHA: String
        }
        struct Family: Decodable {
            let name: String
            let path: String
            let files: [File]
        }
        struct Membership: Decodable {
            let path: String
            let gitBlobSHA: String
            let section: String
            let column: String
        }
        let repository: String
        let revision: String
        let membership: Membership
        let families: [Family]
    }

    private let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Verification/UpstreamExamples")

    @Test("required families come from the pinned upstream TLC table, not the implementation registry")
    func preservesIndependentMembership() throws {
        let inventory = try JSONDecoder().decode(Inventory.self,
            from: Data(contentsOf: directory.appendingPathComponent("inventory.json")))
        let readme = try Data(contentsOf: directory.appendingPathComponent("README.upstream.md"))
        let blob = Data("blob \(readme.count)\0".utf8) + readme
        let digest = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
        #expect(digest == inventory.membership.gitBlobSHA)
        #expect(inventory.repository == "tlaplus/Examples")
        #expect(inventory.revision == "ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10")
        #expect(inventory.membership.path == "README.md")
        #expect(inventory.membership.section == "Validated Examples Included Here")
        #expect(inventory.membership.column == "TLC Model")
        let text = try #require(String(data: readme, encoding: .utf8))
        let section = try #require(text.components(separatedBy: "## Validated Examples Included Here\n").dropFirst().first)
            .components(separatedBy: "\n## Other Examples")[0]
        var required: [String: String] = [:]
        for row in section.components(separatedBy: "\n") where row.hasPrefix("| [") {
            let cells = row.components(separatedBy: "|").dropFirst().dropLast()
                .map { $0.trimmingCharacters(in: .whitespaces) }
            try #require(cells.count == 7)
            guard cells[5] == "✔" else { continue }
            let link = cells[0].components(separatedBy: "](")
            try #require(link.count == 2)
            let path = String(link[1].dropLast())
            let name = String(link[0].dropFirst())
            #expect(required.updateValue(name, forKey: path) == nil)
        }
        #expect(required.count == 78)
        #expect(inventory.families.count == required.count)
        #expect(Set(inventory.families.map(\.path)) == Set(required.keys))
        for family in inventory.families {
            #expect(family.name == required[family.path])
        }
    }

    @Test("each family retains upstream module, configuration, and manifest blob identities")
    func preservesSourceFileInventory() throws {
        let inventory = try JSONDecoder().decode(Inventory.self,
            from: Data(contentsOf: directory.appendingPathComponent("inventory.json")))
        let files = inventory.families.flatMap(\.files)
        #expect(files.count == 733)
        #expect(files.filter { $0.path.hasSuffix(".tla") }.count == 421)
        #expect(files.filter { $0.path.hasSuffix(".cfg") }.count == 234)
        #expect(Set(files.map(\.path)).count == files.count)
        for family in inventory.families {
            #expect(family.files.contains { $0.path == family.path + "/manifest.json" })
            #expect(family.files.contains { $0.path.hasSuffix(".tla") })
            for file in family.files {
                #expect(file.path.hasPrefix(family.path + "/"))
                #expect(!file.path.components(separatedBy: "/").contains(".."))
                #expect(file.gitBlobSHA.count == 40)
                #expect(file.gitBlobSHA.allSatisfy { "0123456789abcdef".contains($0) })
            }
        }
    }

    @Test("coverage retains every required configuration and credits only retained complete evidence")
    func preservesConfigurationCoverage() throws {
        let inventory = try JSONDecoder().decode(Inventory.self,
            from: Data(contentsOf: directory.appendingPathComponent("inventory.json")))
        let coverage = try JSONDecoder().decode(Coverage.self,
            from: Data(contentsOf: directory.appendingPathComponent("coverage.json")))
        let root = directory.deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/cases.json")))
        #expect(coverage.upstreamRevision == inventory.revision)
        #expect(coverage.families.count == inventory.families.count)
        #expect(Set(coverage.families.map(\.path)) == Set(inventory.families.map(\.path)))
        #expect(coverage.dslCriteria.map(\.id) == (1...19).map { String(format: "AC-%02d", $0) })
        let states = ["missing", "implemented", "locally checked", "hosted match"]
        func verifyEvidence(_ evidence: [Coverage.Evidence], status: String, requiresGraph: Bool = true,
            environment: [String: String]? = nil) {
            #expect(states.contains(status))
            if status == "locally checked" || status == "hosted match" {
                #expect(evidence.contains {
                    $0.matches(sourceSHA: coverage.auditedSwiftSHA,
                        developerToolsVersion: coverage.ci.hostedXcode, environment: environment)
                })
            }
            if status == "hosted match" {
                #expect(evidence.contains {
                    $0.matches(sourceSHA: coverage.auditedSwiftSHA,
                        developerToolsVersion: coverage.ci.hostedXcode, environment: environment)
                        && (requiresGraph ? ($0.completeGraph == true && $0.allPropertiesMatch == true) : $0.acceptanceComplete == true)
                        && $0.runURL.hasPrefix("https://github.com/")
                        && $0.artifactURL.hasPrefix("https://github.com/")
                })
            }
        }
        for family in coverage.families {
            let source = try #require(inventory.families.first { $0.path == family.path })
            #expect(family.modules.count == source.files.filter { $0.path.hasSuffix(".tla") }.count)
            #expect(Set(family.modules.map(\.path)) == Set(source.files.filter { $0.path.hasSuffix(".tla") }.map(\.path)))
            #expect(family.modules.allSatisfy { !$0.reason.isEmpty })
            #expect(Set(family.configurations.map(\.configuration)) == Set(source.files.filter { $0.path.hasSuffix(".cfg") }.map(\.path)))
            #expect(Set(family.configurations.map { $0.module + "|" + $0.configuration }).count == family.configurations.count)
            for configuration in family.configurations {
                #expect(configuration.required)
                #expect(family.modules.contains { $0.path == configuration.module })
                verifyEvidence(configuration.evidence, status: configuration.status)
                if let variants = configuration.environmentVariants {
                    #expect(!variants.isEmpty)
                    #expect(configuration.variantReason?.isEmpty == false)
                    #expect(Set(variants.map(\.environment)).count == variants.count)
                    for variant in variants {
                        #expect(!variant.environment.isEmpty)
                        #expect(variant.environment.allSatisfy { !$0.key.isEmpty && !$0.value.isEmpty })
                        verifyEvidence(variant.evidence, status: variant.status, environment: variant.environment)
                        if variant.status != "missing" { #expect(!variant.implementations.isEmpty) }
                        let aggregateRank = try #require(states.firstIndex(of: configuration.status))
                        let variantRank = try #require(states.firstIndex(of: variant.status))
                        #expect(aggregateRank <= variantRank)
                    }
                    if configuration.status == "hosted match" {
                        #expect(configuration.variantAuditComplete == true)
                    }
                }
                if configuration.status != "missing" { #expect(!configuration.implementations.isEmpty) }
                for implementation in configuration.implementations
                    + (configuration.environmentVariants ?? []).flatMap(\.implementations) {
                    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(implementation.file).path))
                    let declaration = try #require(manifest.cases.first { $0.id == implementation.caseID })
                    #expect(declaration.scenario == implementation.scenario)
                    #expect(declaration.sourceInput?.path == "tlaplus/Examples@\(inventory.revision)/\(configuration.module)")
                    for (upstream, fixture) in [(configuration.module, declaration.module), (configuration.configuration, declaration.configuration)] {
                        let pin = try #require(source.files.first { $0.path == upstream })
                        let data = try Data(contentsOf: root.appendingPathComponent("Verification/FiniteGraph/fixtures/" + fixture))
                        let blob = Data("blob \(data.count)\0".utf8) + data
                        let digest = Insecure.SHA1.hash(data: blob).map { String(format: "%02x", $0) }.joined()
                        #expect(digest == pin.gitBlobSHA)
                    }
                }
            }
        }
        for criterion in coverage.dslCriteria {
            verifyEvidence(criterion.evidence, status: criterion.status, requiresGraph: false)
        }
        let graphHarness = try #require(coverage.families.flatMap(\.configurations).first {
            $0.configuration == "specifications/TLC/TestGraphs.cfg"
        })
        let selectableGraphs = (1...13).map(String.init) + ["1a", "DH"]
        let documentedBindings = selectableGraphs.flatMap { graph in
            (1...3).map { workers in ["GRAPH": graph, "K": String(workers)] }
        }
        let variants = try #require(graphHarness.environmentVariants)
        #expect(Set(documentedBindings).isSubset(of: Set(variants.map(\.environment))))
        let reachabilityHarness = try #require(coverage.families.flatMap(\.configurations).first {
            $0.configuration == "specifications/TLC/TestMCReachability.cfg"
        })
        let reachabilityVariants = try #require(reachabilityHarness.environmentVariants)
        #expect(Set(selectableGraphs.map { ["GRAPH": $0] })
            .isSubset(of: Set(reachabilityVariants.map(\.environment))))
    }

    @Test("configuration evidence belongs to one exact source, toolchain, and environment binding")
    func rejectsEvidenceFromDifferentBindings() {
        let environment = ["GRAPH": "1a", "K": "2"]
        let evidence = Coverage.Evidence(sourceSHA: "source", developerToolsVersion: "16.4",
            runURL: "", artifactURL: "", completeGraph: true, allPropertiesMatch: true,
            acceptanceComplete: nil, environment: environment)
        #expect(evidence.matches(sourceSHA: "source", developerToolsVersion: "16.4", environment: environment))
        #expect(!evidence.matches(sourceSHA: "other", developerToolsVersion: "16.4", environment: environment))
        #expect(!evidence.matches(sourceSHA: "source", developerToolsVersion: "16.3", environment: environment))
        let otherBindings: [[String: String]?] = [
            nil, [:], ["GRAPH": "1a"], ["GRAPH": "1a", "K": "1"],
            ["GRAPH": "DH", "K": "2"], ["GRAPH": "1a", "K": "2", "EXTRA": "1"]
        ]
        for binding in otherBindings {
            #expect(!evidence.matches(sourceSHA: "source", developerToolsVersion: "16.4", environment: binding))
        }
    }
}
