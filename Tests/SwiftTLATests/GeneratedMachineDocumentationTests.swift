import Foundation
import Testing

struct GeneratedMachineDocumentationTests {
    @Test("Generated machine guide retains its public contract and fixture parity")
    func guideRetainsPublicContract() throws {
        let root = packageRoot()
        let guide = try String(
            contentsOf: root.appendingPathComponent("Documentation/GeneratedMachines.md"),
            encoding: .utf8
        )

        for term in [
            "Generated `Variables`",
            "Generated `Actions`",
            "`ActionLabel.toInvocation()`",
            "`ActionLabel.init?(invocation:)`",
            "`State(from:)`",
            "`asDictionary`",
            "`availableInvocations()`",
            "`TLAMachineAdapterCanonicalModel`",
            "`TLAMachineAdapterAccess`",
            "`execute(_ invocation: TLAActionInvocation)`",
            "`@TypedVar`",
            "`@TLAValidated`",
            "`_machine`",
            "nested `@TLAObservable` adapter is main-actor isolated",
            "standalone `@TLAObservable` declaration",
            "then awaits the matching callback",
            "Generated `VerificationError`",
            "Generated `runtime`",
            "Generated `verifySpec()`",
            "Generated `transitionMatrix()`",
            "Generated `verifyTransitions()`",
            "Generated `verifyInvariants()`",
            "Generated `synchronousMachineObservation()`",
            "Generated `executeSynchronously(_ invocation: TLAActionInvocation)`"
        ] {
            #expect(guide.contains(term), "Guide is missing public contract term: \(term)")
        }

        for (identifier, file) in fixtureSources {
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

    private var fixtureSources: [String: String] {
        [
            "generated-machine-bounded-model": "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/BoundedCounter.swift",
            "generated-machine-direct-action": "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/DirectAction.swift",
            "generated-machine-actor": "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/ActorAccess.swift",
            "generated-machine-nested-observable": "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/NestedObservable.swift",
            "generated-machine-testing": "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/GeneratedMachineTests.swift",
            "generated-machine-swiftui": "Tests/Fixtures/GeneratedMachineDocumentation/Sources/GeneratedMachineDocumentation/CounterView.swift"
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

    private func packageRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
            directory.deleteLastPathComponent()
        }
        return directory
    }
}
