import Testing
import SwiftParser
import SwiftSyntax
@testable import SwiftTLAPlugin

@testable import SwiftTLA

@Suite("Compiler boundary diagnostics")
struct CompilerBoundaryDiagnosticTests {
    @Test("Explicit unsupported enum raw values are rejected")
    func explicitUnsupportedEnumRawValueIsRejected() throws {
        let source = Parser.parse(source: """
        struct Model {
            enum Phase: Int, FiniteTLAValueDomain {
                case waiting = true
            }
        }
        """)
        let model = try #require(source.statements.first?.item.as(StructDeclSyntax.self))

        do {
            _ = try TLASpecVerifier.collectEnumVariables(from: model.memberBlock.members)
            Issue.record("Expected an explicit unsupported enum raw value to fail.")
        } catch {
            #expect(String(describing: error).contains("requires a supported literal raw value"))
        }
    }

    @Test("Source diagnostics preserve structured parser facts")
    func sourceDiagnosticPreservesParserFacts() {
        let diagnostic = SourceParseDiagnostic(
            code: .unsupportedLanguageConstruct,
            message: "Algorithm declaration 'UnsupportedAlgorithm' is not supported.",
            source: "UnsupportedAlgorithm()",
            sourcePath: ["TLAModel", "spec", "UnsupportedAlgorithm"],
            sourceSpan: .init(location: .utf8Offset(24), utf8Length: 19),
            expected: "a supported Algorithm declaration",
            actual: "unknown Algorithm declaration 'UnsupportedAlgorithm'",
            nextSafeAction: "Use a declaration supported by Algorithm."
        )

        let rendered = diagnostic.renderedMessage
        #expect(rendered.contains("Code: unsupported-language-construct"))
        #expect(rendered.contains("TLAModel.spec.UnsupportedAlgorithm"))
        #expect(rendered.contains("UTF-8 offset 24"))
        #expect(rendered.contains("a supported Algorithm declaration"))
        #expect(rendered.contains("unknown Algorithm declaration 'UnsupportedAlgorithm'"))
        #expect(rendered.contains("Use a declaration supported by Algorithm."))
    }

    @Test("Macro diagnostics preserve structured parser facts")
    func macroDiagnosticEmitsParserFacts() {
        let diagnostic = SourceParseDiagnostic(
            code: .unsupportedLanguageConstruct,
            message: "Algorithm declaration 'UnsupportedAlgorithm' is not supported.",
            source: "UnsupportedAlgorithm()",
            sourcePath: ["TLAModel", "spec", "UnsupportedAlgorithm"],
            sourceSpan: .init(location: .utf8Offset(24), utf8Length: 19),
            expected: "a supported Algorithm declaration",
            actual: "unknown Algorithm declaration 'UnsupportedAlgorithm'",
            nextSafeAction: "Use a declaration supported by Algorithm."
        )
        let source = Parser.parse(source: "struct Example {}")
        guard let declaration = source.statements.first?.item.as(StructDeclSyntax.self) else {
            Issue.record("Expected a struct declaration for macro diagnostic anchoring.")
            return
        }

        let emitted = parserDiagnostic(diagnostic, in: declaration).message
        let requiredFacts = [
            "Code: unsupported-language-construct",
            "Where: TLAModel.spec.UnsupportedAlgorithm, UTF-8 offset 24, length 19.",
            "Expected: a supported Algorithm declaration.",
            "Actual: unknown Algorithm declaration 'UnsupportedAlgorithm'.",
            "Next safe action: Use a declaration supported by Algorithm."
        ]

        #expect(requiredFacts.allSatisfy(emitted.contains))
    }

    @Test("Parser diagnostics prevent partial compilation")
    func parserDiagnosticPreventsPartialCompilation() throws {
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
        let expectedDiagnostic = try #require(parsed.diagnostics.first)
        #expect(expectedDiagnostic.code == .unsupportedLanguageConstruct)
        #expect(expectedDiagnostic.source == "UnsupportedAlgorithmConstruct()")
        #expect(expectedDiagnostic.sourcePath == ["Algorithm", "UnsupportedAlgorithmConstruct"])
        #expect(expectedDiagnostic.sourceSpan.location != .unavailable)
        #expect(expectedDiagnostic.sourceSpan.utf8Length == expectedDiagnostic.source.utf8.count)
        #expect(expectedDiagnostic.expected == "a supported Algorithm declaration")
        #expect(expectedDiagnostic.actual == "unknown Algorithm declaration 'UnsupportedAlgorithmConstruct'")
        #expect(expectedDiagnostic.nextSafeAction == "Use a declaration supported by Algorithm.")

        do {
            _ = try parsed.compile(specificationName: "Rejected")
            Issue.record("A parser diagnostic must prevent compilation publication.")
        } catch let diagnostic as SourceParseDiagnostic {
            #expect(diagnostic == expectedDiagnostic)
        } catch {
            Issue.record("Expected SourceParseDiagnostic, received \(error).")
        }
    }

    @Test("Parser and builder produce the same compilation identity")
    func parserAndBuilderShareCompilationIdentity() throws {
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
        let parsed = SpecParser.parseSpecClosure(
            closure,
            enumDefinitions: [ParserEnumDefinition(
                typeName: "TestControlLabel",
                cases: ["increment": .string("increment")]
            )]
        )
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
}
