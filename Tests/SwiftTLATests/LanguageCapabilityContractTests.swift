import Testing
import SwiftParser
import SwiftSyntax
import SwiftTLAPlugin

@testable import SwiftTLA

@Suite("Language capability contract")
struct LanguageCapabilityContractTests {
    @Test("The ledger covers every declared construct exactly once")
    func ledgerCoversEveryDeclaredConstructExactlyOnce() {
        let capabilities = LanguageCapabilityLedger.all

        #expect(capabilities.count == DeclaredLanguageConstruct.allCases.count)
        #expect(Set(capabilities.map(\.construct)) == Set(DeclaredLanguageConstruct.allCases))
        #expect(capabilities.allSatisfy { capability in
            LanguageCapabilityDimension.allCases.allSatisfy {
                capability.dimensions[$0] != nil
            }
        })
    }

    @Test("Construct references retain parser classifications and authored spellings")
    func constructReferencesRetainParserClassificationsAndAuthoredNames() {
        let awaitReference = LanguageConstructReference.declared(
            construct: .awaitCondition,
            authoredName: "Await"
        )
        let whenReference = LanguageConstructReference.declared(
            construct: .awaitCondition,
            authoredName: "When"
        )
        let unknownReference = LanguageConstructReference.unregistered(sourceName: "NotAConstruct")

        #expect(awaitReference.construct == .awaitCondition)
        #expect(whenReference.construct == .awaitCondition)
        #expect(awaitReference.authoredName == "Await")
        #expect(whenReference.authoredName == "When")
        #expect(unknownReference == .unregistered(sourceName: "NotAConstruct"))
        #expect(unknownReference.construct == nil)
        #expect(unknownReference.authoredName == "NotAConstruct")
    }

    @Test("Parser diagnostics preserve complete capability facts")
    func capabilityDiagnosticPreservesCompleteFactsInParserRendering() {
        let sourceSpan = SpecParser.SourceParseDiagnostic.SourceSpan(
            location: .utf8Offset(24),
            utf8Length: 19
        )
        let capability = LanguageCapabilityDiagnostic(
            code: .unsupportedConstruct,
            construct: .unregistered(sourceName: "UnsupportedAlgorithm"),
            operation: .sourceDecoding,
            source: "UnsupportedAlgorithm()",
            sourceSpan: sourceSpan,
            expected: "an admitted Algorithm declaration",
            actual: "unregistered declaration 'UnsupportedAlgorithm'",
            nextSafeAction: "Use an admitted Algorithm declaration."
        )
        let parserDiagnostic = SpecParser.SourceParseDiagnostic(
            capability: capability
        )

        #expect(parserDiagnostic.renderedMessage.contains("Code: unsupported-language-capability"))
        #expect(parserDiagnostic.renderedMessage.contains("UnsupportedAlgorithm"))
        #expect(parserDiagnostic.renderedMessage.contains("source decoding"))
        #expect(parserDiagnostic.renderedMessage.contains("UTF-8 offset 24"))
        #expect(parserDiagnostic.renderedMessage.contains("an admitted Algorithm declaration"))
        #expect(parserDiagnostic.renderedMessage.contains("unregistered declaration 'UnsupportedAlgorithm'"))
        #expect(parserDiagnostic.renderedMessage.contains("Use an admitted Algorithm declaration."))
    }

    @Test("Macro diagnostics do not degrade capability errors to their headline")
    func macroDiagnosticEmitsEveryCapabilityFact() {
        let capability = LanguageCapabilityDiagnostic(
            code: .unsupportedConstruct,
            construct: .unregistered(sourceName: "UnsupportedAlgorithm"),
            operation: .sourceDecoding,
            source: "UnsupportedAlgorithm()",
            sourcePath: ["TLAModel", "spec", "UnsupportedAlgorithm"],
            sourceSpan: .init(location: .utf8Offset(24), utf8Length: 19),
            expected: "an admitted Algorithm declaration",
            actual: "unregistered declaration 'UnsupportedAlgorithm'",
            nextSafeAction: "Use an admitted Algorithm declaration."
        )
        let parserDiagnostic = SpecParser.SourceParseDiagnostic(
            capability: capability
        )
        let source = Parser.parse(source: "struct Example {}")
        guard let declaration = source.statements.first?.item.as(StructDeclSyntax.self) else {
            Issue.record("Expected a struct declaration for macro diagnostic anchoring.")
            return
        }

        let emitted = SwiftTLAPlugin.parserDiagnostic(parserDiagnostic, in: declaration).message
        let requiredFacts = [
            "Code: unsupported-language-capability",
            "Construct: UnsupportedAlgorithm.",
            "Operation: source decoding.",
            "Where: TLAModel.spec.UnsupportedAlgorithm, UTF-8 offset 24, length 19.",
            "Expected: an admitted Algorithm declaration.",
            "Actual: unregistered declaration 'UnsupportedAlgorithm'.",
            "Next safe action: Use an admitted Algorithm declaration."
        ]

        #expect(requiredFacts.allSatisfy(emitted.contains))
        #expect(!requiredFacts.allSatisfy(capability.headline.contains))
    }

    @Test("Unsupported capabilities cannot advertise compilation support")
    func rejectsUnsupportedCapabilityWithSupportedCompilation() {
        let invalid = capability(
            .genericFairness,
            compilation: .supported
        )
        let records = replacing(.genericFairness, with: invalid)

        #expect(throws: LanguageCapabilityLedgerError.unsupportedCompilation(.genericFairness)) {
            try LanguageCapabilityLedger.validate(records)
        }
    }

    @Test("Sequential Algorithm fairness has supported construction")
    func sequentialAlgorithmFairnessHasSupportedConstruction() {
        let capability = LanguageCapabilityLedger.capability(for: .sequentialAlgorithmFairness)

        #expect(capability.status == .supported)
        #expect(capability.dimensions.sourceDecoding == .supported)
        #expect(capability.dimensions.resultBuilderConstruction == .supported)
        #expect(capability.dimensions.compilation == .supported)
        #expect(capability.dimensions.tlaRendering == .supported)
        #expect(capability.dimensions.plusCalRendering == .supported)
        #expect(capability.dimensions.execution == .supported)
        #expect(capability.dimensions.boundedConformance == .supported)
    }

    @Test("Supported capabilities require a construction route")
    func rejectsSupportedCapabilityWithoutConstructionRoute() {
        let invalid = capability(
            .awaitCondition,
            sourceDecoding: .unsupported,
            resultBuilderConstruction: .notApplicable
        )
        let records = replacing(.awaitCondition, with: invalid)

        #expect(throws: LanguageCapabilityLedgerError.supportedCapabilityWithoutConstructionRoute(.awaitCondition)) {
            try LanguageCapabilityLedger.validate(records)
        }
    }

    @Test("The ledger rejects duplicate construct records")
    func rejectsDuplicateCapabilityRecords() {
        let records = LanguageCapabilityLedger.all + [LanguageCapabilityLedger.capability(for: .awaitCondition)]

        #expect(throws: LanguageCapabilityLedgerError.duplicateRecord(.awaitCondition)) {
            try LanguageCapabilityLedger.validate(records)
        }
    }

    @Test("The ledger rejects missing construct records")
    func rejectsMissingCapabilityRecords() {
        let records = LanguageCapabilityLedger.all.filter { $0.construct != .awaitCondition }

        #expect(throws: LanguageCapabilityLedgerError.missingRecord(.awaitCondition)) {
            try LanguageCapabilityLedger.validate(records)
        }
    }

    @Test("Parsed capability diagnostics prevent partial compilation")
    func parsedCapabilityDiagnosticPreventsPartialCompilation() throws {
        let closure = try #require(
            Parser.parse(source: """
            {
                Algorithm("Rejected") {
                    UnsupportedAlgorithmConstruct()
                }
            }
            """).statements.first?.item.as(ClosureExprSyntax.self)
        )
        let parsed = SpecParser.parseSpecClosure(closure)

        #expect(parsed.sourceAlgorithms.isEmpty)
        #expect(parsed.diagnostics.count == 1)
        let expectedDiagnostic = try #require(parsed.diagnostics.first?.capabilityDiagnostic)
        #expect(expectedDiagnostic.code == .unsupportedConstruct)
        #expect(expectedDiagnostic.construct == .unregistered(sourceName: "UnsupportedAlgorithmConstruct"))
        #expect(expectedDiagnostic.operation == .sourceDecoding)
        #expect(expectedDiagnostic.source == "UnsupportedAlgorithmConstruct()")
        #expect(expectedDiagnostic.sourcePath == ["Algorithm", "UnsupportedAlgorithmConstruct"])
        #expect(expectedDiagnostic.sourceSpan.location != .unavailable)
        #expect(expectedDiagnostic.sourceSpan.utf8Length == expectedDiagnostic.source.utf8.count)
        #expect(expectedDiagnostic.expected == "a registered Algorithm declaration with supported source decoding")
        #expect(expectedDiagnostic.actual == "unregistered Algorithm declaration 'UnsupportedAlgorithmConstruct'")
        #expect(expectedDiagnostic.nextSafeAction == "Use an admitted Algorithm declaration.")

        do {
            _ = try parsed.compile(specificationName: "Rejected")
            Issue.record("A parser capability diagnostic must prevent compilation publication.")
        } catch let diagnostic as LanguageCapabilityDiagnostic {
            #expect(diagnostic == expectedDiagnostic)
        } catch {
            Issue.record("Expected LanguageCapabilityDiagnostic, received \(error).")
        }
    }

    @Test("Parser and builder compile admitted Algorithm declarations identically")
    func parserAndBuilderShareAnAdmittedAlgorithmCompilationIdentity() throws {
        let source = """
        {
            Algorithm("CanonicalAlgorithm", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                    Stop()
                }
            })
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(closure)
        let parsedCompilation = try parsed.compile(specificationName: "CanonicalAlgorithm")
        let builderCompilation = try TLASpec("CanonicalAlgorithm") {
            Algorithm("CanonicalAlgorithm", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                    Stop()
                }
            })
        }.compile()

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsedCompilation.identity == builderCompilation.identity)
    }

    private func replacing(
        _ construct: DeclaredLanguageConstruct,
        with replacement: LanguageCapability
    ) -> [LanguageCapability] {
        LanguageCapabilityLedger.all.map { capability in
            capability.construct == construct ? replacement : capability
        }
    }

    private func capability(
        _ construct: DeclaredLanguageConstruct,
        sourceDecoding: LanguageCapabilityDimensionStatus? = nil,
        resultBuilderConstruction: LanguageCapabilityDimensionStatus? = nil,
        compilation: LanguageCapabilityDimensionStatus? = nil
    ) -> LanguageCapability {
        let existing = LanguageCapabilityLedger.capability(for: construct)
        return LanguageCapability(
            construct: existing.construct,
            status: existing.status,
            dimensions: .init(
                sourceDecoding: sourceDecoding ?? existing.dimensions.sourceDecoding,
                resultBuilderConstruction: resultBuilderConstruction ?? existing.dimensions.resultBuilderConstruction,
                compilation: compilation ?? existing.dimensions.compilation,
                tlaRendering: existing.dimensions.tlaRendering,
                plusCalRendering: existing.dimensions.plusCalRendering,
                execution: existing.dimensions.execution,
                boundedConformance: existing.dimensions.boundedConformance
            ),
            boundary: existing.boundary,
            nextSafeAction: existing.nextSafeAction
        )
    }
}
