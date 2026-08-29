import Foundation
import Testing

struct GeneratedMachineDocumentationTests {
    @Test("README clock examples compile from their exact fixture sources")
    func readmeClockExamplesMatchCompilingFixtures() throws {
        let root = packageRoot()
        let readme = try String(
            contentsOf: root.appendingPathComponent("README.md"),
            encoding: .utf8
        )

        for (identifier, file) in readmeExampleSources {
            let fixture = try String(
                contentsOf: root.appendingPathComponent(file),
                encoding: .utf8
            )
            #expect(
                swiftSnippet(id: identifier, in: readme) == fixture.trimmingCharacters(in: .newlines),
                "README snippet does not match fixture: \(identifier)"
            )
        }
    }

    @Test("Generated machine guide examples match compiling fixtures")
    func guideExamplesMatchCompilingFixtures() throws {
        let root = packageRoot()
        let guide = try String(
            contentsOf: root.appendingPathComponent("Documentation/GeneratedMachines.md"),
            encoding: .utf8
        )

        for (identifier, file) in completeExampleSources {
            let fixture = try String(
                contentsOf: root.appendingPathComponent(file),
                encoding: .utf8
            )
            #expect(
                swiftSnippet(id: identifier, in: guide) == fixture.trimmingCharacters(in: .newlines),
                "Guide snippet does not match fixture: \(identifier)"
            )
        }
    }

    @Test("Generated machine guide links and public inventory resolve to supported sources")
    func guideLinksAndInventoryResolve() throws {
        let root = packageRoot()
        let guideURL = root.appendingPathComponent("Documentation/GeneratedMachines.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        for destination in localLinkDestinations(in: guide) {
            let components = destination.split(separator: "#", maxSplits: 1).map(String.init)
            let documentURL = destination.hasPrefix("#")
                ? guideURL
                : guideURL.deletingLastPathComponent().appendingPathComponent(components[0])
            #expect(FileManager.default.fileExists(atPath: documentURL.path), "Missing linked document: \(destination)")

            if destination.contains("#") {
                let anchor = destination.hasPrefix("#") ? String(destination.dropFirst()) : components[1]
                let document = try String(contentsOf: documentURL, encoding: .utf8)
                #expect(
                    headingAnchors(in: document).contains(anchor),
                    "Missing linked heading: \(destination)"
                )
            }
        }

        let inventory = publicInventory(in: guide)
        for (name, source, declaration) in supportedInventory {
            #expect(inventory.contains(name), "Public inventory is missing: \(name)")
            let sourceText = try String(contentsOf: root.appendingPathComponent(source), encoding: .utf8)
            #expect(sourceText.contains(declaration), "Source declaration is missing: \(declaration)")
        }

    }

    @Test("Generated-machine Markdown and DocC retain the typed public boundary")
    func documentationRetainsTypedBoundary() throws {
        let root = packageRoot()
        let guide = try String(
            contentsOf: root.appendingPathComponent("Documentation/GeneratedMachines.md"),
            encoding: .utf8
        )
        let docc = try String(
            contentsOf: root.appendingPathComponent("Sources/SwiftTLA/SwiftTLA.docc/GeneratedMachineSurface.md"),
            encoding: .utf8
        )
        let macroDocc = try String(
            contentsOf: root.appendingPathComponent("Sources/SwiftTLAMacros/SwiftTLAMacros.docc/SwiftTLAMacros.md"),
            encoding: .utf8
        )

        for term in ["Transition", "Action", "State", "send(_:)", "isEnabled(_:)"] {
            #expect(guide.contains(term), "Markdown guide is missing typed term: \(term)")
            #expect(docc.contains(term), "SwiftTLA DocC is missing typed term: \(term)")
        }
        #expect(macroDocc.contains("TLAModel"), "Macro DocC is missing TLAModel")

    }

    @Test("Generated machine documentation fixture compiles and exercises its stated macOS behavior")
    func fixtureCompilesAndExercisesDocumentedBehavior() throws {
        let fixture = packageRoot().appendingPathComponent("Tests/Fixtures/GeneratedMachineDocumentation")
        let result = try runXcodebuild(in: fixture)
        #expect(
            result.status == 0,
            "Generated-machine fixture failed its macOS behavior tests:\n\(outputTail(result.output))"
        )
    }

    private var completeExampleSources: [String: String] {
        [
            "generated-machine-bounded-model":
                "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/BoundedCounter.swift",
            "generated-machine-direct-action":
                "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/DirectAction.swift",
            "generated-machine-swiftui":
                "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/CounterView.swift",
            "generated-machine-actor":
                "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/ActorAccess.swift",
            "generated-machine-testing":
                "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/GeneratedMachineTests.swift"
        ]
    }

    private var readmeExampleSources: [String: String] {
        [
            "readme-clock-model":
                "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/READMEClockModel.swift",
            "readme-clock-swiftui":
                "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/READMEClockView.swift"
        ]
    }

    private var supportedInventory: [(String, String, String)] {
        [
            ("`@TLAModel`", "Sources/SwiftTLAMacros/Macros.swift", "public macro TLAModel"),
            ("`GeneratedMachineError`", "Sources/SwiftTLA/GeneratedMachineError.swift", "public enum GeneratedMachineError"),
            ("Generated `Action`", "Sources/SwiftTLAPlugin/MacroExpander.swift", "public enum Action"),
            ("Generated `Transition`", "Sources/SwiftTLAPlugin/MacroExpander+GeneratedMachineStorage.swift", "public struct Transition"),
            ("Generated `Actor`", "Sources/SwiftTLAPlugin/MacroExpander+Actor.swift", "public actor Actor"),
        ]
    }

    private func swiftSnippet(id: String, in guide: String) -> String {
        guard let identifier = guide.range(of: "**Example ID:** `\(id)`"),
              let opening = guide.range(of: "```swift", range: identifier.upperBound..<guide.endIndex),
              let closing = guide.range(of: "```", range: opening.upperBound..<guide.endIndex)
        else {
            Issue.record("Missing Swift snippet for \(id)")
            return ""
        }
        return String(guide[opening.upperBound..<closing.lowerBound])
            .trimmingCharacters(in: .newlines)
    }

    private func publicInventory(in guide: String) -> String {
        guard let start = guide.range(of: "## API reference") else {
            Issue.record("Guide is missing its API reference section")
            return ""
        }
        return guide[start.upperBound..<guide.endIndex]
            .split(separator: "\n")
            .filter { $0.hasPrefix("|") }
            .joined(separator: "\n")
    }

    private func localLinkDestinations(in markdown: String) -> [String] {
        markdown.split(separator: "\n").compactMap { line in
            guard let opening = line.range(of: "]("),
                  let closing = line[opening.upperBound...].firstIndex(of: ")")
            else {
                return nil
            }
            let destination = String(line[opening.upperBound..<closing])
            return destination.hasPrefix("http") ? nil : destination
        }
    }

    private func headingAnchors(in markdown: String) -> Set<String> {
        Set(markdown.split(separator: "\n").compactMap { line in
            let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#"), !title.isEmpty else { return nil }
            return title.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }
                .replacingOccurrences(of: " ", with: "-")
        })
    }

    private func runXcodebuild(in fixture: URL) throws -> (status: Int32, output: String) {
        try withSerializedExternalPackageBuild {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.currentDirectoryURL = fixture
            process.arguments = [
                "-quiet",
                "-scheme", "GeneratedMachineDocumentation-Package",
                "-destination", "platform=macOS",
                "-parallel-testing-enabled", "NO",
                "-parallel-testing-worker-count", "1",
                "-jobs", "1",
                "test",
                "CODE_SIGNING_ALLOWED=NO"
            ]
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftTLA-generated-machine-docs-\(UUID().uuidString).log")
            _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? FileManager.default.removeItem(at: outputURL) }

            process.standardOutput = output
            process.standardError = output
            try process.run()
            process.waitUntilExit()
            try output.close()

            return (
                process.terminationStatus,
                String(data: try Data(contentsOf: outputURL), encoding: .utf8) ?? ""
            )
        }
    }

    private func outputTail(_ output: String) -> String {
        String(output.suffix(4_000))
    }
}
