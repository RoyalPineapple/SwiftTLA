import CryptoKit
import Foundation
import Testing

struct UpstreamCorpusInventoryTests {
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
}
