import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@Suite("PlusCal Algorithm renderer")
struct AlgorithmPlusCalRendererTests {
    private enum ProcessStep: String, CaseIterable {
        case `repeat`
        case done
    }

    private enum ProcedureStep: String, CaseIterable {
        case enter
        case start
        case finished
    }

    private enum ProcedureName: String, CaseIterable {
        case work
    }

    private enum Node: String, FiniteTLAValueDomain {
        case left
        case right

        static var defaultValue: Self { .left }
        static let finiteValues: [Node] = [.left, .right]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    @Test("renders process declarations, source labels, and structured statements")
    func rendersProcessAlgorithm() throws {
        let algorithm = Algorithm("RenderedProcess", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            let flags = scope.sharedVar("flags", initial: Function<Node, Bool>.literal((.left, false), (.right, false)))
            let _ = scope.sharedVar("sentinel", initial: "author text")
            Each(Node.all, fairness: .strong, scoped: { node, scope in
                let local = scope.localVar("local", initial: 0)
                While(ProcessStep.repeat, count < 2) {
                    When(count >= 0)
                    Assert(count < 3)
                    With(SetExpr<Int>.literal(1, 2)) { picked in
                        Assign(local, to: picked)
                    }
                    Choose(3...4) { chosen in
                        Assign(count, to: chosen)
                    }
                    If(node == .left) {
                        Assign(flags, to: flags.updating(node, to: true))
                    } else: {
                        Either {
                            Goto(ProcessStep.repeat)
                        } or: {
                            Skip()
                        }
                    }
                }
                Do(ProcessStep.done) { Stop() }
            })
        })

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("---- MODULE RenderedProcess ----"))
        #expect(rendered.contains("count = 0"))
        #expect(rendered.contains("sentinel = \"author text\""))
        #expect(rendered.contains("(*--algorithm RenderedProcess {"))
        #expect(rendered.contains("fair+ process (pcalProcess1 \\in {\"left\", \"right\"})"))
        #expect(rendered.contains("local = 0"))
        #expect(rendered.contains("repeat: while ((count < 2)) {"))
        #expect(rendered.contains("await (count >= 0);"))
        #expect(rendered.contains("assert (count < 3);"))
        #expect(rendered.components(separatedBy: "with (").count == 3)
        #expect(rendered.contains("\\in {1, 2})"))
        #expect(rendered.contains("\\in {3, 4})"))
        #expect(rendered.contains("flags := [flags EXCEPT ![self] = TRUE];"))
        #expect(rendered.contains("either {"))
        #expect(rendered.contains("goto repeat;"))
        #expect(rendered.contains("goto Done;"))
        #expect(rendered.contains("} *)"))
    }

    @Test("compilation prepares process identifiers for PlusCal")
    func preparesProcessIdentifiers() throws {
        let algorithm = Algorithm("ProcessIdentifier", scoped: { scope in
            let flags = scope.sharedVar("flags", initial: Function<Node, Bool>.literal((.left, false), (.right, false)))
            Each(Node.all) { node in
                Do(ProcessStep.done) {
                    Assign(flags, to: flags.updating(node, to: true))
                    Stop()
                }
            }
        })

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("flags := [flags EXCEPT ![self] = TRUE];"))
    }

    @Test("imports Integers when rendering a negative formal value")
    func rendersNegativeFormalValue() throws {
        let algorithm = Algorithm("Negative", scoped: { scope in
            let _: SharedVariable<Int> = scope.sharedVar("previous", initial: -1)
            Do(TestControlLabel.stop) { Stop() }
        })

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("EXTENDS Integers, Naturals, Sequences, FiniteSets"))
        #expect(rendered.contains("previous = -1"))
    }

    @Test("renders legal quantified binders in authored expressions")
    func rendersLegalQuantifiedBinder() throws {
        let algorithm = Algorithm("QuantifiedBinder", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            Do(TestControlLabel.stop) {
                When(StateExpr.forAll(
                    .setLiteral([.int(0), .int(1)]),
                    "item_1",
                    StateExpr.variable("item_1") >= count.expr
                ))
                Stop()
            }
        })

        let compilation = try TLASpec("QuantifiedBinder") { algorithm }.compile()
        let rendered = try compilation.renderedPlusCalBundle().root.tla
        let renderedTLA = compilation.renderedTLAModuleBundle().root.tla

        #expect(rendered.contains("await \\A item_1 \\in {0, 1} : (item_1 >= count);"))
        #expect(renderedTLA.contains("\\A item_1 \\in {0, 1}"))
    }

    @Test("keeps prelude helpers outside and state helpers inside define")
    func rendersStructuredDeclarationSections() throws {
        let spec = TLASpec("Sections") {
            FormalDefinition("Bound", parameters: [], body: .value(.int(2)))
            Algorithm("Sections", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                FormalDefinition(
                    "UsesCount",
                    parameters: [],
                    body: count.expr == 0,
                    plusCalPhase: .define
                )
                Do(TestControlLabel.done) { Stop() }
            })
        }

        let rendered = try spec.compile().renderedPlusCalBundle().root.tla
        let algorithmRange = try #require(rendered.range(of: "(*--algorithm Sections"))
        let preludeRange = try #require(rendered.range(of: "Bound == 2"))
        let defineRange = try #require(rendered.range(of: "define {"))
        let stateHelperRange = try #require(rendered.range(of: "UsesCount =="))
        #expect(preludeRange.lowerBound < algorithmRange.lowerBound)
        #expect(defineRange.lowerBound < stateHelperRange.lowerBound)
    }

    @Test("renders formal definitions in their declaration section")
    func rendersDirectFormalDefinitionInDefine() throws {
        let algorithm = Algorithm("DirectSections", scoped: { scope in
            let count = scope.sharedVar("count", initial: 0)
            FormalDefinition("Ready", taking: Int.self, plusCalPhase: .define) { _ in
                count == 0
            }
            Do(TestControlLabel.done) { Stop() }
        })

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)
        let variableRange = try #require(rendered.range(of: "count = 0"))
        let defineRange = try #require(rendered.range(of: "define {"))
        let definitionRange = try #require(rendered.range(of: "Ready("))
        let actionRange = try #require(rendered.range(of: "done:"))
        #expect(variableRange.lowerBound < defineRange.lowerBound)
        #expect(defineRange.lowerBound < definitionRange.lowerBound)
        #expect(definitionRange.lowerBound < actionRange.lowerBound)
    }

    @Test("renders typed properties outside the authored Algorithm")
    func rendersTopLevelTypedProperty() throws {
        let spec = TLASpec("CompilerProperty") {
            Algorithm("Counter", scoped: { scope in
                let _ = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.done) { Stop() }
            })
            Invariant("CountIsZero") { StateExpr.variable("count") == 0 }
        }

        let rendered = try spec.compile().renderedPlusCalBundle().root.tla

        #expect(rendered.contains("CountIsZero =="))
    }

    @Test("compiled authored properties preserve their lowered identities")
    func compiledAuthoredPropertiesPreserveLoweredIdentities() throws {
        let source = TLASpec("PropertyIdentity") {
            Invariant("TopLevel") { true }
            Algorithm("PropertyIdentity") {
                Do(TestControlLabel.done) { Stop() }
                Invariant("AuthoredInvariant") { true }
                Eventually("AuthoredTemporal", true)
            }
        }
        let lowered = try source.loweredSourceModel()
        let closure = try FormalModuleClosure.resolve(root: lowered)
        let layout = CompiledLayout(spec: lowered, closure: closure)
        var lowerer = CompiledLowerer(spec: lowered, closure: closure, layout: layout)
        let semantics = try lowerer.lower(spec: lowered)
        let sourcePlan = try #require(lowered.authoredPlusCalAlgorithmPlan)
        let plan = try lowerer.authoredPlusCalPlan(sourcePlan)

        #expect(semantics.invariants.map(\.id) == [.init(ordinal: 0), .init(ordinal: 1)])
        #expect(semantics.temporalProperties.map(\.id) == [.init(ordinal: 2)])
        #expect(plan.properties.map(\.id) == [.init(ordinal: 1), .init(ordinal: 2)])
        #expect(plan.properties.map(\.name) == ["AuthoredInvariant", "AuthoredTemporal"])
    }

    @Test("compilation leaves standard process termination to the PlusCal translator")
    func plansTranslatorTermination() throws {
        let algorithm = Algorithm("TranslatorTermination") {
            Each(Node.all) { _ in
                Do(ProcessStep.done) { Stop() }
            }
            Eventually("Termination", All(Node.all) { Finished($0) })
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("Termination ==") == false)
    }

    @Test("compilation rejects a custom property with the translator termination name")
    func rejectsCustomTerminationProperty() {
        let algorithm = Algorithm("CustomTermination") {
            Each(Node.all) { _ in
                Do(ProcessStep.done) { Stop() }
            }
            Eventually("Termination", true)
        }

        do {
            _ = try renderedSourceAlgorithmPlusCal(algorithm)
            Issue.record("Expected compilation to reject the duplicate rendered definition")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .duplicateRenderedModuleDefinition)
            #expect(diagnostic.stage == .rendering)
            #expect(diagnostic.actual == "a distinct property named Termination")
        } catch {
            Issue.record("Unexpected diagnostic: \(error)")
        }
    }

    @Test("renders nested finite-domain property binders distinctly")
    func rendersNestedFiniteDomainPropertyBindersDistinctly() throws {
        let spec = TLASpec("DistinctPropertyBinders") {
            Algorithm("DistinctPropertyBinders") {
                Do(ProcessStep.done) { Stop() }
                Invariant("Distinct") {
                    All(Node.all) { first in
                        All(Node.all) { second in
                            first == second
                        }
                    }
                }
            }
        }

        let rendered = try spec.compile().renderedPlusCalBundle().root.tla
        let definition = try #require(rendered.split(separator: "\n").first { $0.hasPrefix("Distinct ==") })
        let binders = definition.components(separatedBy: "\\A ").dropFirst().compactMap { clause in
            clause.split(separator: " ").first.map(String.init)
        }

        #expect(binders.count == 2)
        #expect(Set(binders).count == 2)
        #expect(definition.contains("\(binders[0]) = \(binders[1])"))
    }

    @Test("renders nested finite-domain constraint binders distinctly")
    func rendersNestedFiniteDomainConstraintBindersDistinctly() throws {
        let spec = TLASpec("DistinctConstraintBinders") {
            Algorithm("DistinctConstraintBinders") {
                Do(ProcessStep.done) { Stop() }
                StateConstraint(
                    All(Node.all) { first in
                        All(Node.all) { second in
                            first == second
                        }
                    }
                )
            }
        }

        let rendered = try spec.compile().renderedPlusCalBundle().root.tla
        let definition = try #require(rendered.split(separator: "\n").first { $0.hasPrefix("StateConstraint ==") })
        let binders = definition.components(separatedBy: "\\A ").dropFirst().compactMap { clause in
            clause.split(separator: " ").first.map(String.init)
        }

        #expect(binders.count == 2)
        #expect(Set(binders).count == 2)
    }

    @Test("#spec preserves distinct authored binder locations")
    func macroPreservesDistinctAuthoredBinderLocations() throws {
        let spec = #spec("MacroBinderLocations") {
            Algorithm("MacroBinderLocations") {
                Do(ProcessStep.done) { Stop() }
                Invariant("Distinct") {
                    All(Node.all) { first in
                        All(Node.all) { second in
                            first == second
                        }
                    }
                }
            }
        }

        let rendered = try spec.compile().renderedPlusCalBundle().root.tla
        let definition = try #require(rendered.split(separator: "\n").first { $0.hasPrefix("Distinct ==") })
        let binders = definition.components(separatedBy: "\\A ").dropFirst().compactMap { clause in
            clause.split(separator: " ").first.map(String.init)
        }

        #expect(binders.count == 2)
        #expect(Set(binders).count == 2)
        #expect(definition.contains("\(binders[0]) = \(binders[1])"))
    }

    @Test("rejects unresolved authored declaration dependencies")
    func rejectsMissingDeclarationDependency() {
        #expect(throws: CompilationDiagnostic.self) {
            try AuthoredPlusCalDeclarationSections([
                .init(name: "UsesMissing", text: "UsesMissing == TRUE", phase: .define, dependencies: ["Missing"])
            ])
        }
    }

    @Test("rejects cyclic authored declaration dependencies")
    func rejectsCyclicDeclarationDependency() {
        #expect(throws: CompilationDiagnostic.self) {
            try AuthoredPlusCalDeclarationSections([
                .init(name: "First", text: "First == TRUE", phase: .define, dependencies: ["Second"]),
                .init(name: "Second", text: "Second == TRUE", phase: .define, dependencies: ["First"])
            ])
        }
    }

    @Test("renders procedure parameters with compiled state names")
    func rendersProcedureParametersWithCompiledStateNames() throws {
        let algorithm = Algorithm("Procedures", scoped: { scope in
            let output = scope.sharedVar("output", initial: 0)
            Procedure(ProcedureName.work, parameters: Int.self, scoped: { value, scope in
                let offset = scope.localVar("offset", initial: 1)
                Do(ProcedureStep.enter) {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            })
            Do(ProcedureStep.start) { Call(ProcedureName.work, with: 7) }
            Do(ProcedureStep.finished) { Stop() }
        })

        let compilation = try TLASpec("Procedures") { algorithm }.compile()
        let rendered = try compilation.renderedPlusCalBundle().root.tla
        let renderedTLA = compilation.renderedTLAModuleBundle().root.tla

        #expect(rendered.contains("procedure work(parameter0)"))
        #expect(rendered.contains("enter:"))
        #expect(rendered.contains("output := (parameter0 + offset);"))
        #expect(rendered.contains("call work(7);"))
        #expect(rendered.contains("{\n  start:"))
        #expect(renderedTLA.contains("VARIABLES pc, output, stack, parameter0, offset"))
    }

    @Test("procedure call capture avoids authored binders and retains tail return")
    func procedureCallCaptureAvoidsAuthoredBindersAndRetainsTailReturn() throws {
        let model = AlgorithmModel(
            name: "ScheduledTailCall",
            components: [
                .shared(.init(root: "output", initialization: .value(.int(0)))),
                .procedure(.init(
                    name: "outer",
                    parameters: [],
                    components: [
                        .step(.init(label: .init(name: "enter"), statements: [
                            .letBinding(variable: "__atomic_0", value: .int(1), [
                                .set(target: .root("output"), value: .variable("__atomic_0")),
                                .call(target: "inner", arguments: [.variable("output")]),
                                .return
                            ])
                        ]))
                    ]
                )),
                .procedure(.init(
                    name: "inner",
                    parameters: [.init(root: "input", initial: .int(0), swiftTypeName: "Int")],
                    components: [
                        .step(.init(label: .init(name: "enter"), statements: [.return]))
                    ]
                )),
                .step(.init(label: .init(name: "start"), statements: [
                    .call(target: "outer", arguments: [])
                ])),
                .step(.init(label: .init(name: "finished"), statements: [.stop]))
            ]
        )

        let rendered = try renderedSourceAlgorithmPlusCal(Algorithm(model: model))
        let authoredBinding = try #require(rendered.range(of: "with (__atomic_0 = 1)"))
        let capturedArgument = try #require(rendered.range(of: "with (__atomic_1 = output)"))
        let assignment = try #require(rendered.range(of: "output := __atomic_0;"))
        let call = try #require(rendered.range(of: "call inner(__atomic_1);"))
        let tailReturn = try #require(rendered.range(of: "return;", range: call.upperBound..<rendered.endIndex))
        #expect(authoredBinding.lowerBound < capturedArgument.lowerBound)
        #expect(capturedArgument.lowerBound < assignment.lowerBound)
        #expect(assignment.lowerBound < call.lowerBound)
        #expect(call.lowerBound < tailReturn.lowerBound)
    }

    @Test("compilation renders the authored Algorithm and its state constraint")
    func rendersAuthoredAlgorithmAndStateConstraint() throws {
        let spec = TLASpec("Retained") {
            Algorithm("Retained", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.stop) { Stop() }
                StateConstraint(count < 2)
            })
        }

        let compilation = try spec.compile()
        let module = try compilation.renderedPlusCalBundle().root.tla

        #expect(module.contains("(*--algorithm Retained {"))
        #expect(module.contains("} *)\nStateConstraint == (count < 2)\n===="))
        #expect(!module.contains("\\* StateConstraint"))
        #expect(compilation.description.actions.contains(where: { $0.name == "stop" }))
    }

    @Test("renders authored module context around the Algorithm comment")
    func rendersAuthoredModuleContext() throws {
        let spec = TLASpec("Context") {
            Extends(.integers)
            Constant("N", 2)
            FormalDefinition("Seed", parameters: [], body: .variable("N"))
            Symmetry("member", [1, 2] as Set<Int>)
            Algorithm("Context", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.stop) { Stop() }
                Invariant("Bounded") { count.expr <= 2 }
            })
        }

        let module = try spec.compile().renderedPlusCalBundle().root.tla

        #expect(module.contains("CONSTANTS N"))
        #expect(module.contains("TLC"))
        #expect(module.contains("Seed == 2"))
        #expect(module.contains("(*--algorithm Context {"))
        #expect(module.contains("Bounded == (count <= 2)"))
        #expect(module.contains("Symmmember == Permutations({1, 2})"))
        let seed = try #require(module.range(of: "Seed == 2"))
        let algorithm = try #require(module.range(of: "(*--algorithm Context {"))
        #expect(seed.lowerBound < algorithm.lowerBound)
    }

    @Test("standard module declarations preserve canonical order")
    func standardModuleDeclarationsPreserveCanonicalOrder() throws {
        let spec = TLASpec("Modules") {
            Extends(.naturals)
            Extends(.finiteSets)
            Algorithm("Modules", scoped: { scope in
                let _ = scope.sharedVar("count", initial: 0)
                Do(TestControlLabel.stop) { Stop() }
            })
        }

        #expect(spec.extendsModules == [StandardModule.integers, .naturals, .finiteSets])
        #expect(try spec.compile().renderedPlusCalBundle().root.tla.contains(
            "EXTENDS Integers, Naturals, FiniteSets, Sequences"
        ))
    }

    @Test("authored PlusCal renders mutual LET recursion from bound operator identities")
    func rendersBoundMutualLocalRecursion() throws {
        let expression = StateExpr.letIn(
            [
                LocalOperator("First", body: .recursiveCall("Second", [])),
                LocalOperator("Second", body: .recursiveCall("First", []))
            ],
            .recursiveCall("First", [])
        )
        let specification = TLASpec("MutualLocalRecursion") {
            Algorithm("MutualLocalRecursion") {
                Do(TestControlLabel.stop) {
                    When(expression)
                    Stop()
                }
            }
        }

        let rendered = try specification.compile().renderedPlusCalBundle().root.tla

        #expect(rendered.contains("RECURSIVE First, Second"))
    }

    @Test("nested LET shadowing keeps recursion with the bound declaration")
    func rendersBoundNestedLocalRecursion() throws {
        let inner = LocalOperator("Repeat", body: .recursiveCall("Repeat", []))
        let outer = LocalOperator(
            "Repeat",
            body: .letIn([inner], .recursiveCall("Repeat", []))
        )
        let expression = StateExpr.letIn([outer], .recursiveCall("Repeat", []))
        let specification = TLASpec("NestedLocalRecursion") {
            Algorithm("NestedLocalRecursion") {
                Do(TestControlLabel.stop) {
                    When(expression)
                    Stop()
                }
            }
        }

        let rendered = try specification.compile().renderedPlusCalBundle().root.tla

        #expect(rendered.components(separatedBy: "RECURSIVE Repeat").count == 2)
    }
}
