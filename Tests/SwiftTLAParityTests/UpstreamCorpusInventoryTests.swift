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
        }
        struct Configuration: Decodable {
            let module: String
            let configuration: String
            let required: Bool
            let status: String
            let implementations: [Implementation]
            let evidence: [Evidence]
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
        let states = Set(["missing", "implemented", "locally checked", "hosted match"])
        func verifyEvidence(_ evidence: [Coverage.Evidence], status: String, requiresGraph: Bool = true) {
            #expect(states.contains(status))
            if status == "locally checked" || status == "hosted match" {
                #expect(evidence.contains {
                    $0.sourceSHA == coverage.auditedSwiftSHA && $0.developerToolsVersion == coverage.ci.hostedXcode
                })
            }
            if status == "hosted match" {
                #expect(evidence.contains {
                    $0.sourceSHA == coverage.auditedSwiftSHA
                        && $0.developerToolsVersion == coverage.ci.hostedXcode
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
                if configuration.status != "missing" { #expect(!configuration.implementations.isEmpty) }
                for implementation in configuration.implementations {
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
    }
}
