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
            #expect(error == .invalidEnumRawValue(typeName: "Phase", caseName: "waiting"))
        }
    }

    @Test("Unsupported enum declarations diagnose the offending source")
    func unsupportedEnumDeclarationsPointToSource() throws {
        for (members, tokenName, occurrence) in [
            ("enum Phase: String, CaseIterable, FiniteTLAValueDomain { case first; static let finiteValues = makeDomain() }", "finiteValues", 0),
            ("enum Phase: String, TLAValueType { case first; var tlaValue: TLAValue { encode(rawValue) } }", "tlaValue", 0),
            ("enum Phase: String, TLAValueType { case first = \"same\", second = \"same\" }", "second", 0),
            ("enum Phase: String, TLAValueType { case first; case first }", "first", 1),
            ("enum Other: Int, TLAValueType { case first = 1 }; enum Phase: Int, TLAValueType { case first = true }", "first", 1),
            ("enum Phase: String, TLAValueType { case first }; enum Phase: String, TLAValueType { case second }", "Phase", 1)
        ] {
            let source = Parser.parse(source: """
            struct InvalidModel {
                \(members)
                static var spec: TLASpec { #spec {} }
            }
            """)
            let model = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
            let token = try #require(Array(model.tokens(viewMode: .sourceAccurate))
                .filter { $0.text == tokenName }.dropFirst(occurrence).first)

            do {
                _ = try TLASpecVerifier.parseAndVerify(model)
                Issue.record("Unsupported enum declaration must fail")
            } catch let error as ModelMacroError {
                let diagnostic = modelMacroDiagnostic(error, in: model)
                #expect(diagnostic.node.positionAfterSkippingLeadingTrivia == token.positionAfterSkippingLeadingTrivia)
            }
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

    @Test("A generated value type error points to the offending state declaration")
    func generatedTypeErrorPointsToStateDeclaration() throws {
        for body in [
            """
            #spec { scope in
                let count: SharedVariable<Int> = scope.sharedVar(initial: true)
            }
            """,
            """
            #spec {
                let counter = Algorithm(scoped: { scope in
                    let count: SharedVariable<Int> = scope.sharedVar(initial: true)
                    Do(Control.advance) { Stop() }
                })
                counter
            }
            """,
            """
            #spec {
                let counter = Algorithm(scoped: { scope in
                    Each(Control.all, scoped: { _, process in
                        let count: LocalVariable<Int> = process.localVar(initial: true)
                        Do(Control.advance) { Stop() }
                    })
                })
                counter
            }
            """
        ] {
            let source = Parser.parse(source: """
            struct InvalidModel {
                enum Control: String, CaseIterable, FiniteTLAValueDomain {
                    case advance
                }
                static var spec: TLASpec {
                    \(body)
                }
            }
            """)
            let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
            let count = try #require(source.tokens(viewMode: .sourceAccurate).first { $0.text == "count" })

            do {
                _ = try TLASpecVerifier.parseAndVerify(declaration)
                Issue.record("A Boolean initializer must not satisfy an integer state declaration")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.contains("variables.count"))
                #expect(diagnostic.sourceOffset == count.positionAfterSkippingLeadingTrivia.utf8Offset)
                let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
                #expect(emitted.node.positionAfterSkippingLeadingTrivia == count.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    @Test("Generated action type errors point to their labeled step")
    func generatedActionTypeErrorPointsToStep() throws {
        for (body, action) in [
            ("Do(Step.advance) { Assign(count, to: true) }", "actions.advance"),
            ("""
            Procedure(ProcedureName.helper) {
                Do(Step.advance) { Assign(count, to: true); Return() }
            }
            Do(Step.start) { Call(ProcedureName.helper) }
            Do(Step.finished) { Stop() }
            """, "actions.procedure.helper.advance")
        ] {
            let source = Parser.parse(source: """
        struct InvalidModel {
            enum Step: String, CaseIterable, FiniteTLAValueDomain { case start, advance, finished }
            enum ProcedureName: String, CaseIterable, FiniteTLAValueDomain { case helper }
            static var spec: TLASpec {
                #spec {
                    let algorithm = Algorithm(scoped: { scope in
                        let count: SharedVariable<Int> = scope.sharedVar(initial: 0)
                        \(body)
                    })
                    algorithm
                }
            }
        }
        """)
            let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
            let step = try #require(source.tokens(viewMode: .sourceAccurate).first { $0.text == "Do" })

            do {
                _ = try TLASpecVerifier.parseAndVerify(declaration)
                Issue.record("A Boolean action value must not update an integer state")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.contains(action))
                #expect(diagnostic.sourceOffset == step.positionAfterSkippingLeadingTrivia.utf8Offset)
                let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
                #expect(emitted.node.positionAfterSkippingLeadingTrivia == step.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    @Test("A duplicate procedure diagnostic points to the second declaration")
    func duplicateProcedurePointsToSecondDeclaration() throws {
        let source = Parser.parse(source: """
        struct InvalidModel {
            enum Routine: String, CaseIterable, FiniteTLAValueDomain { case scan }
            enum Step: String, CaseIterable, FiniteTLAValueDomain { case start, first, second, finished }
            static var spec: TLASpec {
                #spec {
                    let algorithm = Algorithm {
                        Procedure(Routine.scan) { Do(Step.first) { Return() } }
                        Procedure(Routine.scan) { Do(Step.second) { Return() } }
                        Do(Step.start) { Call(Routine.scan) }
                        Do(Step.finished) { Stop() }
                    }
                    algorithm
                }
            }
        }
        """)
        let model = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let duplicate = try #require(Array(source.tokens(viewMode: .sourceAccurate))
            .filter { $0.text == "Procedure" }.last)

        do {
            _ = try TLASpecVerifier.parseAndVerify(model)
            Issue.record("A duplicate procedure must fail at its second declaration")
        } catch let diagnostic as SourceParseDiagnostic {
            #expect(diagnostic.message.contains("Procedure 'scan' is declared more than once"))
            #expect(diagnostic.sourceSpan.location == .utf8Offset(
                duplicate.positionAfterSkippingLeadingTrivia.utf8Offset))
            let emitted = parserDiagnostic(diagnostic, in: model)
            #expect(emitted.node.positionAfterSkippingLeadingTrivia == duplicate.positionAfterSkippingLeadingTrivia)
        }
    }

    @Test("Generated property type errors point to their predicate registration")
    func generatedPropertyTypeErrorPointsToRegistration() throws {
        for (handle, registration, insideAlgorithm, path) in [
            ("Invariant", "Claim { 1 }", false, "invariants.Claim"),
            ("Reachable", "Claim { 1 }", false, "reachabilityProperties.Claim"),
            ("Invariant", "Claim { 1 }", true, "invariants.Claim"),
            ("Eventually", "Claim(1)", false, "temporalProperties.Claim"),
            ("Eventually", "Claim(1)", true, "temporalProperties.Claim")
        ] {
            let source = Parser.parse(source: """
        struct InvalidModel {
            enum Step: String, CaseIterable, FiniteTLAValueDomain { case advance }
            static var spec: TLASpec {
                #spec {
                    let Claim = \(handle)()
                    \(insideAlgorithm ? "" : registration)
                    let algorithm = Algorithm(scoped: { scope in
                        let count = scope.sharedVar(initial: 0)
                        Do(Step.advance) { Stop() }
                        \(insideAlgorithm ? registration : "")
                    })
                    algorithm
                }
            }
        }
        """)
            let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
            let registration = try #require(source.tokens(viewMode: .sourceAccurate).filter { $0.text == "Claim" }.last)

            do {
                _ = try TLASpecVerifier.parseAndVerify(declaration)
                Issue.record("An integer predicate must not satisfy a Boolean property")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.contains(path))
                #expect(diagnostic.sourceOffset == registration.positionAfterSkippingLeadingTrivia.utf8Offset)
                let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
                #expect(emitted.node.positionAfterSkippingLeadingTrivia == registration.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    @Test("Generated refinement errors point to the mapping or declaration")
    func generatedRefinementErrorsPointToSource() throws {
        for (mappings, token, path) in [
            ("[.init(Var<Int>(\"value\"), from: true)]", "true", "refinements.Refines.mappings.value"),
            ("[]", "Refinement", "refinements.Refines.mappings")
        ] {
            let source = Parser.parse(source: """
        struct InvalidModel {
            static var spec: TLASpec {
                #spec { scope in
                    let abstract = TLASpec("Abstract") {
                        let value = Var<Int>("value")
                        Variable(value, 0)
                        SwiftTLA.Action("stay") { value.stays }
                    }
                    let count = scope.sharedVar(initial: 0)
                    let target = Instance("Target", of: abstract)
                    target
                    let Refines = Refinement(instance: target,
                        mappings: \(mappings))
                    Refines
                }
            }
        }
        """)
            let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
            let location = try #require(source.tokens(viewMode: .sourceAccurate).first { $0.text == token })

            do {
                _ = try TLASpecVerifier.parseAndVerify(declaration)
                Issue.record("An incompatible or missing refinement mapping must fail compilation")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.contains(path))
                #expect(diagnostic.sourceOffset == location.positionAfterSkippingLeadingTrivia.utf8Offset)
                let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
                #expect(emitted.node.positionAfterSkippingLeadingTrivia == location.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    @Test("Parameter and checking-register type errors point to their declarations")
    func typedInputErrorsPointToDeclarations() throws {
        for (input, name, path) in [
            ("let enabled = scope.parameter(as: Bool.self, in: Set<Int>([1]))", "enabled", "parameters.enabled"),
            ("let freeze = scope.checkingRegister(as: Int.self, initial: false)", "freeze", "checkingRegisters.freeze")
        ] {
            let source = Parser.parse(source: """
        struct InvalidModel {
            enum Step: String, CaseIterable, FiniteTLAValueDomain { case advance }
            static var spec: TLASpec {
                #spec { scope in
                    \(input)
                    let counter = Algorithm(scoped: { scope in
                        let count = scope.sharedVar(initial: 0)
                        Do(Step.advance) { Stop() }
                    })
                    counter
                }
            }
        }
        """)
            let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
            let inputName = try #require(source.tokens(viewMode: .sourceAccurate).first { $0.text == name })

            do {
                _ = try TLASpecVerifier.parseAndVerify(declaration)
                Issue.record("An incompatible input value must fail at its declaration")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.contains(path))
                #expect(diagnostic.sourceOffset == inputName.positionAfterSkippingLeadingTrivia.utf8Offset)
                let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
                #expect(emitted.node.positionAfterSkippingLeadingTrivia == inputName.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    @Test("Constraint and assumption type errors point to their predicates")
    func booleanModelPredicatesPointToSource() throws {
        for (declaration, algorithmPredicate, token, path, clause) in [
            ("Constraint(1)", "", "Constraint", "constraint", 0),
            ("Constraint(true)\nConstraint(1)", "", "Constraint", "constraint", 1),
            ("Assume(1)", "", "Assume", "assume", 0),
            ("Assume(true)\nAssume(1)", "", "Assume", "assume", 1),
            ("", "StateConstraint(1)", "StateConstraint", "constraint", 0),
            ("", "StateConstraint(true)\nStateConstraint(1)", "StateConstraint", "constraint", 1)
        ] {
            let source = Parser.parse(source: """
        struct InvalidModel {
            enum Step: String, CaseIterable, FiniteTLAValueDomain { case advance }
            static var spec: TLASpec {
                #spec {
                    \(declaration)
                    let algorithm = Algorithm(scoped: { scope in
                        let count = scope.sharedVar(initial: 0)
                        \(algorithmPredicate)
                        Do(Step.advance) { Stop() }
                    })
                    algorithm
                }
            }
        }
        """)
            let model = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
            let predicate = try #require(Array(source.tokens(viewMode: .sourceAccurate)).last { $0.text == token })

            do {
                _ = try TLASpecVerifier.parseAndVerify(model)
                Issue.record("An integer predicate must not satisfy a Boolean model condition")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("nativeMachine.\(path)[\(clause)] → "))
                #expect(diagnostic.sourceOffset == predicate.positionAfterSkippingLeadingTrivia.utf8Offset)
                let emitted = modelCompilationDiagnostic(diagnostic, in: model)
                #expect(emitted.node.positionAfterSkippingLeadingTrivia == predicate.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    @Test("An incompatible scenario binding points to its supplied value")
    func incompatibleScenarioBindingPointsToValue() throws {
        let source = Parser.parse(source: """
        struct InvalidModel {
            enum Step: String, CaseIterable, FiniteTLAValueDomain { case advance }
            static var spec: TLASpec {
                #spec { scope in
                    let limit = scope.parameter(as: Int.self, in: 0...3)
                    let counter = Algorithm(scoped: { scope in
                        let count = scope.sharedVar(initial: 0)
                        Do(Step.advance) { Stop() }
                    })
                    counter
                    let Invalid = Validation { Bind(limit, to: true) }
                    Invalid
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let suppliedValue = try #require(source.tokens(viewMode: .sourceAccurate).first { $0.text == "true" })

        do {
            _ = try TLASpecVerifier.parseAndVerify(declaration)
            Issue.record("A Boolean value must not satisfy an integer scenario parameter")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path.contains("validation.Invalid"))
            #expect(diagnostic.sourceOffset == suppliedValue.positionAfterSkippingLeadingTrivia.utf8Offset)
            let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
            #expect(emitted.node.positionAfterSkippingLeadingTrivia == suppliedValue.positionAfterSkippingLeadingTrivia)
        }
    }

    @Test("Unsupported scenario symmetry points to the selected handle")
    func temporalScenarioSymmetryPointsToSelection() throws {
        let source = Parser.parse(source: """
        struct InvalidModel {
            enum Member: String, CaseIterable, FiniteTLAValueDomain { case a, b }
            static var spec: TLASpec {
                #spec { scope in
                    let value = scope.sharedVar(initial: 0)
                    let members = Symmetry(Set(Member.all))
                    members
                    let progress = Eventually()
                    progress(value == 1)
                    let check = Validation {}.usingSymmetry(members)
                    check
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let selected = try #require(Array(source.tokens(viewMode: .sourceAccurate))
            .last { $0.text == "members" })

        do {
            _ = try TLASpecVerifier.parseAndVerify(declaration)
            Issue.record("Temporal checking with selected symmetry must fail")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unsupportedSymmetryReduction)
            #expect(diagnostic.path == "validation.check.symmetry")
            #expect(diagnostic.sourceOffset == selected.positionAfterSkippingLeadingTrivia.utf8Offset)
            let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
            #expect(emitted.node.positionAfterSkippingLeadingTrivia == selected.positionAfterSkippingLeadingTrivia)
        }
    }

    @Test("A fairness profile with initial-and-next checking points to its selection")
    func fairnessProfileBehaviorPointsToSelection() throws {
        let source = Parser.parse(source: """
        struct InvalidModel {
            enum Step: String, CaseIterable { case ncs }
            static var spec: TLASpec {
                #spec { scope in
                    let algorithm = Algorithm(scoped: { scope in
                        Each(Set<Int>([0]), fairness: .weak) { _ in
                            Do(Step.ncs) { Goto(Step.ncs) }
                        }
                    })
                    algorithm
                    let profile = FairnessProfile(excluding: [Step.ncs])
                    profile
                    let check = Validation {}.usingFairness(profile).behavior(.initialAndNext)
                    check
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let selected = try #require(Array(source.tokens(viewMode: .sourceAccurate))
            .last { $0.text == "profile" })

        do {
            _ = try TLASpecVerifier.parseAndVerify(declaration)
            Issue.record("A fairness profile requires specification behavior")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.path == "validation.check.fairness")
            #expect(diagnostic.sourceOffset == selected.positionAfterSkippingLeadingTrivia.utf8Offset)
            let emitted = modelCompilationDiagnostic(diagnostic, in: declaration)
            #expect(emitted.node.positionAfterSkippingLeadingTrivia == selected.positionAfterSkippingLeadingTrivia)
        }
    }

    @Test("A refinement selected with symmetry points to the scenario selection")
    func refinementScenarioSymmetryPointsToSelection() throws {
        let source = Parser.parse(source: """
        struct InvalidModel {
            enum Member: String, CaseIterable, FiniteTLAValueDomain { case a, b }
            enum Step: String, CaseIterable { case stay }
            static var spec: TLASpec {
                #spec { scope in
                    let abstract = TLASpec("Abstract") {
                        let value = Var<Int>("value")
                        Variable(value, 0)
                        SwiftTLA.Action("stay") { value.stays }
                    }
                    let value = scope.sharedVar(initial: 0)
                    Do(Step.stay) { Assign(value, to: value) }
                    let target = Instance("Abstract", of: abstract)
                    target
                    let Refines = Refinement(instance: target,
                        mappings: [.init(Var<Int>("value"), from: value)])
                    Refines
                    let members = Symmetry(Set(Member.all))
                    members
                    let check = Validation {}.usingSymmetry(members)
                    check
                }
            }
        }
        """)
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        let selected = try #require(Array(source.tokens(viewMode: .sourceAccurate))
            .last { $0.text == "members" })

        do {
            _ = try TLASpecVerifier.parseAndVerify(declaration)
            Issue.record("Refinement checking with selected symmetry must fail")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unsupportedSymmetryReduction)
            #expect(diagnostic.path == "validation.check.symmetry")
            #expect(diagnostic.actual == "Refines")
            #expect(diagnostic.sourceOffset == selected.positionAfterSkippingLeadingTrivia.utf8Offset)
        }
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
