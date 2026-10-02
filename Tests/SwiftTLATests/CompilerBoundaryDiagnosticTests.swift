import Foundation
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
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))

        do {
            _ = try TLASpecVerifier.collectEnumVariables(from: declaration.memberBlock.members)
            Issue.record("Expected an explicit unsupported enum raw value to fail.")
        } catch let error as ModelMacroError {
            #expect(error == .invalidEnumRawValue(caseName: "waiting"))
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
                let rejected = Algorithm(label: "Rejected") {
                    UnsupportedAlgorithmConstruct()
                }
            }
            """).statements.first?.item.as(ClosureExprSyntax.self)
        )
        let parsed = SpecParser.parseSpecClosure(named: "Rejected", closure)

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

        let imported = TLASpec("ImportingRejected") { Import(parsed) }
        for specification in [
            parsed,
            imported,
            TLASpec("TransitiveImport") { Import(imported) },
            TLASpec("InstantiatingRejected") { Instance("RejectedInstance", of: parsed) }
        ] {
            do {
                _ = try specification.compile()
                Issue.record("A parser diagnostic must prevent compilation publication.")
            } catch let diagnostic as SourceParseDiagnostic {
                #expect(diagnostic == expectedDiagnostic)
            } catch {
                Issue.record("Expected SourceParseDiagnostic, received \(error).")
            }
        }
    }

    @Test("Parser and result builder normalize repeated standard-module declarations")
    func standardModuleDeclarationsShareNormalization() throws {
        let closure = try #require(Parser.parse(source:
            "{ Extends(.sequences, .integers, .sequences) }"
        ).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "StandardModules", closure)
        let built = TLASpec("StandardModules") {
            Extends(.sequences, .integers, .sequences)
        }
        #expect(parsed.extendsModules == built.extendsModules)
        #expect(try parsed.compile().identity == built.compile().identity)
    }

    @Test("Parser and result builder produce the same compilation identity")
    func parserAndResultBuilderShareCompilationIdentity() throws {
        let source = """
        {
            let IdentityAlgorithm = Algorithm(scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                    Stop()
                }
            })
            IdentityAlgorithm
        }
        """
        let closure = try #require(Parser.parse(source: source).statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "IdentityAlgorithm",
            closure,
            sourceTypes: .init(enums: [SourceEnum(
                typeName: "TestControlLabel",
                cases: [("increment", .string("increment"))]
            )])
        )
        let parsedCompilation = try parsed.compile()
        let resultBuilderCompilation = try TLASpec("IdentityAlgorithm") {
            Algorithm("IdentityAlgorithm", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                    Stop()
                }
            })
        }.compile()

        #expect(parsed.diagnostics.isEmpty)
        #expect(parsedCompilation.identity == resultBuilderCompilation.identity)
    }

    @Test("Bound algorithm and validation use their Swift binding identities")
    func boundBuildersUseSwiftBindingIdentities() throws {
        let source = """
        {
            let counter = Algorithm(scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(TestControlLabel.increment) {
                    Assign(count, to: count + 1)
                    Stop()
                }
            })
            counter
            let complete = Validation {}
            complete
        }
        """
        let labelledSource = source
            .replacingOccurrences(of: "Algorithm(scoped:", with: "Algorithm(label: \"Counter\", scoped:")
            .replacingOccurrences(of: "Validation {}", with: "Validation(label: \"Complete\") {}")
        let metadata = SourceTypeMetadata(enums: [SourceEnum(typeName: "TestControlLabel",
            cases: [("increment", .string("increment"))])])
        let closure = try #require(Parser.parse(source: source)
            .statements.first?.item.as(ClosureExprSyntax.self))
        let labelledClosure = try #require(Parser.parse(source: labelledSource)
            .statements.first?.item.as(ClosureExprSyntax.self))
        let parsed = SpecParser.parseSpecClosure(named: "BoundBuilders", closure, sourceTypes: metadata)
        let labelled = SpecParser.parseSpecClosure(named: "BoundBuilders", labelledClosure, sourceTypes: metadata)

        #expect(parsed.diagnostics.isEmpty)
        #expect(labelled.diagnostics.isEmpty)
        #expect(parsed.sourceAlgorithms.map(\.model.name) == ["counter"])
        #expect(parsed.validationScenarios.map(\.name) == ["complete"])
        #expect(try parsed.compile().identity == labelled.compile().identity)
    }

    @Test("Algorithm and Validation require immutable bindings without positional names")
    func buildersRequireImmutableIdentityBindings() throws {
        for body in [
            "Algorithm {}",
            "Validation {}",
            "Algorithm(\"Named\") {}",
            "Validation(\"Named\") {}",
            "let algorithm = Algorithm(\"Named\") {}",
            "let validation = Validation(\"Named\") {}",
            "let algorithm = Algorithm(_name: \"Faked\") {}",
            "let validation = Validation(_name: \"Faked\") {}",
            "var algorithm = Algorithm {}",
            "var validation = Validation {}"
        ] {
            let closure = try #require(Parser.parse(source: "{ \(body) }")
                .statements.first?.item.as(ClosureExprSyntax.self))
            let parsed = SpecParser.parseSpecClosure(named: "InvalidBinding", closure)

            #expect(parsed.diagnostics.count == 1)
            #expect(parsed.diagnostics[0].message.contains("immutable let binding"))
            #expect(parsed.diagnostics[0].sourceSpan.location != .unavailable)
            #expect(parsed.sourceAlgorithms.isEmpty)
            #expect(parsed.validationScenarios.isEmpty)
        }
    }

    @Test("Builder display labels require nonempty literals")
    func builderDisplayLabelsRequireLiterals() throws {
        for body in [
            "let algorithm = Algorithm(label: \"\") {}",
            "let validation = Validation(label: \"\") {}",
            "let algorithm = Algorithm(label: \"bad \\(value)\") {}",
            "let validation = Validation(label: \"bad \\(value)\") {}"
        ] {
            let closure = try #require(Parser.parse(source: "{ \(body) }")
                .statements.first?.item.as(ClosureExprSyntax.self))
            let parsed = SpecParser.parseSpecClosure(named: "InvalidLabel", closure)

            #expect(parsed.diagnostics.count == 1)
            #expect(parsed.sourceAlgorithms.isEmpty)
            #expect(parsed.validationScenarios.isEmpty)
        }
    }
}
