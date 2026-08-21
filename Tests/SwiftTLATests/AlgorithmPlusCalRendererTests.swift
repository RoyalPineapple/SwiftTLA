import Testing
@testable import SwiftTLA

@Suite("PlusCal Algorithm renderer")
struct AlgorithmPlusCalRendererTests {
    private enum Node: String, FiniteDomainKey {
        case left
        case right

        static let formalDomain: [Node] = [.left, .right]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal-renderer.node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    @Test("renders process declarations, source labels, and structured statements without lowering")
    func rendersProcessAlgorithm() throws {
        let algorithm = Algorithm("Rendered Process") {
            let count = SharedVar("count", initial: 0)
            let flags = SharedVar("flags", initial: Function<Node, Bool>.literal((.left, false), (.right, false)))
            let sentinel = SharedVar("sentinel", initial: "__pcal_self")
            count
            flags
            sentinel
            Each(Node.all, fairness: .strong) { node in
                let local = LocalVar("local", initial: 0)
                local
                While(ProgramLabel(rawValue: "repeat"), count < 2) {
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
                            Goto(ProgramLabel(rawValue: "repeat"))
                        } or: {
                            Skip()
                        }
                    }
                }
                Do(ProgramLabel(rawValue: "done")) { Stop() }
            }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("---- MODULE RenderedProcess ----"))
        #expect(rendered.contains("count = 0"))
        #expect(rendered.contains("sentinel = \"__pcal_self\""))
        #expect(rendered.contains("(*--algorithm Rendered Process {"))
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

    @Test("imports Integers when rendering a negative formal value")
    func rendersNegativeFormalValue() throws {
        let algorithm = Algorithm("Negative") {
            let previous = SharedVar("previous", initial: -1)
            previous
            Do("stop") { Stop() }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("EXTENDS Naturals, Integers, Sequences, FiniteSets"))
        #expect(rendered.contains("previous = -1"))
    }

    @Test("keeps prelude helpers outside and state helpers inside define")
    func rendersStructuredDeclarationSections() throws {
        let model = AlgorithmModel(name: "Sections", components: [
            .shared(.init(root: "count", initial: .value(.int(0)))),
            .step(.init(label: .init(name: "done"), statements: [.stop]))
        ])
        let module = AuthoredPlusCalModule(
            name: "Sections",
            extendsModules: ["Naturals"],
            constants: [],
            definitionsBeforeInstances: ["Bound == 2"],
            instances: [],
            definitionsAfterInstances: [],
            algorithm: model,
            defineDeclarations: ["UsesCount == count = 0"],
            postTranslationDeclarations: []
        )

        let rendered = try AlgorithmPlusCalRenderer(model: model).render(module)
        let algorithmRange = try #require(rendered.range(of: "(*--algorithm Sections"))
        let preludeRange = try #require(rendered.range(of: "Bound == 2"))
        let defineRange = try #require(rendered.range(of: "define {"))
        let stateHelperRange = try #require(rendered.range(of: "UsesCount == count = 0"))
        #expect(preludeRange.lowerBound < algorithmRange.lowerBound)
        #expect(defineRange.lowerBound < stateHelperRange.lowerBound)
    }

    @Test("direct Algorithm export retains formal definition phase")
    func rendersDirectFormalDefinitionInDefine() throws {
        let algorithm = Algorithm("Direct Sections") {
            let count = SharedVar("count", initial: 0)
            count
            FormalDefinition("Ready", taking: Int.self, plusCalPhase: .define) { _ in
                count == 0
            }
            Do("done") { Stop() }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)
        let variableRange = try #require(rendered.range(of: "count = 0"))
        let defineRange = try #require(rendered.range(of: "define {"))
        let definitionRange = try #require(rendered.range(of: "Ready(value0) =="))
        let actionRange = try #require(rendered.range(of: "done:"))
        #expect(variableRange.lowerBound < defineRange.lowerBound)
        #expect(defineRange.lowerBound < definitionRange.lowerBound)
        #expect(definitionRange.lowerBound < actionRange.lowerBound)
    }

    @Test("renders typed properties outside the authored Algorithm")
    func rendersTopLevelTypedProperty() throws {
        let spec = TLASpec("Compiler Property") {
            Algorithm("Counter") {
                let count = SharedVar("count", initial: 0)
                count
                Do("done") { Stop() }
            }
            Invariant("CountIsZero") { StateExpr.variable("count") == 0 }
        }

        let rendered = try spec.compile().renderedPlusCalBundle().root.tla

        #expect(rendered.contains("CountIsZero =="))
    }

    @Test("rejects unresolved authored declaration dependencies")
    func rejectsMissingDeclarationDependency() {
        #expect(throws: AlgorithmPlusCalRenderDiagnostic.self) {
            try AuthoredPlusCalDeclarationSections([
                .init(name: "UsesMissing", text: "UsesMissing == TRUE", phase: .define, dependencies: ["Missing"])
            ])
        }
    }

    @Test("rejects cyclic authored declaration dependencies")
    func rejectsCyclicDeclarationDependency() {
        #expect(throws: AlgorithmPlusCalRenderDiagnostic.self) {
            try AuthoredPlusCalDeclarationSections([
                .init(name: "First", text: "First == TRUE", phase: .define, dependencies: ["Second"]),
                .init(name: "Second", text: "Second == TRUE", phase: .define, dependencies: ["First"])
            ])
        }
    }

    @Test("renders the PlusCal brace control grammar literally")
    func rendersBraceControlGrammar() throws {
        let loop = AlgorithmLabelModel(name: "loop")
        let model = AlgorithmModel(name: "Grammar", components: [
            .shared(.init(root: "count", initial: .value(.int(0)))),
            .step(.init(label: loop, statements: [
                .letBinding(variable: "bound", value: .value(.int(1)), [
                    .with(variable: "member", source: .setLiteral([.value(.int(1)), .value(.int(2))]), [
                        .ifElse(.value(.bool(true)), [
                            .either([.skip], [.goto(loop)])
                        ], [])
                    ])
                ])
            ], loopCondition: .value(.bool(true))))
        ])

        let rendered = try AlgorithmPlusCalRenderer(model: model).render()

        #expect(rendered.contains("loop: while (TRUE) {"))
        #expect(rendered.contains("with (bound = 1) {"))
        #expect(rendered.contains("with (member \\in {1, 2}) {"))
        #expect(rendered.contains("if (TRUE) {"))
        #expect(rendered.contains("either {"))
        #expect(rendered.contains("} or {"))
        #expect(rendered.contains("goto loop;"))
    }

    @Test("renders supported process fairness in the PlusCal header")
    func rendersProcessFairness() throws {
        let model = AlgorithmModel(name: "Fair", components: [
            .process(.init(
                typeName: "Process",
                domain: [.int(1)],
                fairness: .weak,
                components: [.step(.init(label: .init(name: "done"), statements: [.stop]))]
            ))
        ])

        let rendered = try AlgorithmPlusCalRenderer(model: model).render()

        #expect(rendered.contains("fair process (pcalProcess1 \\in {1})"))
    }

    @Test("uses the PlusCal self identifier without shadowing authored names")
    func rendersHygienicProcessIdentifiers() throws {
        let model = AlgorithmModel(name: "Hygiene", components: [
            .shared(.init(root: "pcalProcess1", initial: .value(.int(0)))),
            .process(.init(
                typeName: "Process",
                domain: [.int(1)],
                fairness: .none,
                components: [.step(.init(
                    label: .init(name: "advance"),
                    statements: [.set(target: .root("pcalProcess1"), value: .variable("__pcal_self"))]
                ))]
            ))
        ])

        let rendered = try AlgorithmPlusCalRenderer(model: model).render()

        #expect(rendered.contains("process (pcalProcess1_2 \\in {1})"))
        #expect(rendered.contains("pcalProcess1 := self;"))
    }

    @Test("renders a sequential body and procedures directly from Algorithm IR")
    func rendersSequentialProcedureAlgorithm() throws {
        let algorithm = Algorithm("Procedures") {
            let output = SharedVar("output", initial: 0)
            output
            Procedure("work", parameters: Int.self) { value in
                let offset = LocalVar("offset", initial: 1)
                offset
                Do(ProgramLabel(rawValue: "enter")) {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            }
            Do(ProgramLabel(rawValue: "start")) { Call("work", with: 7) }
            Do(ProgramLabel(rawValue: "finished")) { Stop() }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("procedure work(parameter0)"))
        #expect(rendered.contains("enter:"))
        #expect(rendered.contains("output := (parameter0 + offset);"))
        #expect(rendered.contains("call work(7);"))
        #expect(rendered.contains("{\n  start:"))
    }

    @Test("reports source nodes that have no direct PlusCal spelling")
    func reportsUnsupportedSourceNode() {
        let model = AlgorithmModel(name: "Unsupported", components: [.propertyBoundary])

        do {
            _ = try AlgorithmPlusCalRenderer(model: model).render()
            Issue.record("Expected an unsupported-source diagnostic")
        } catch let diagnostic as AlgorithmPlusCalRenderDiagnostic {
            #expect(diagnostic.failedConcept == "semantic-free PlusCal source rendering")
            #expect(diagnostic.path == "components[0]")
            #expect(diagnostic.expected == "a directly renderable PlusCal declaration")
            #expect(diagnostic.actual == "property boundary")
            #expect(diagnostic.stateChange == .none)
            #expect(!diagnostic.nextSafeAction.isEmpty)
        } catch {
            Issue.record("Expected AlgorithmPlusCalRenderDiagnostic, got \(error)")
        }
    }

    @Test("rejects higher-order anonymous lambdas instead of printing invalid PlusCal")
    func rejectsResidualAnonymousFormalLambda() {
        let model = AlgorithmModel(name: "HigherOrder", components: [
            .shared(.init(
                root: "output",
                initial: .operatorApplication(
                    .reference("Apply", arity: 1),
                    [.operator(.lambda(.init(parameters: ["value"], body: .variable("value"))))]
                )
            ))
        ])

        do {
            _ = try AlgorithmPlusCalRenderer(model: model).render()
            Issue.record("Expected an unsupported higher-order lambda diagnostic")
        } catch let diagnostic as AlgorithmPlusCalRenderDiagnostic {
            #expect(diagnostic.path == "shared[0].initial")
            #expect(diagnostic.expected.contains("named operator reference"))
            #expect(diagnostic.actual.contains("residual anonymous formal lambda"))
            #expect(diagnostic.stateChange == .none)
        } catch {
            Issue.record("Expected AlgorithmPlusCalRenderDiagnostic, got \(error)")
        }
    }

    @Test("retains authored Algorithm source for independent PlusCal rendering")
    func retainsAuthoredAlgorithmOnTheLoweredSpec() throws {
        let spec = TLASpec("Retained") {
            Algorithm("Retained") {
                let count = SharedVar("count", initial: 0)
                count
                Do("stop") { Stop() }
                StateConstraint(count < 2)
            }
        }

        let module = try spec.compile().renderedPlusCalBundle().root.tla

        #expect(module.contains("(*--algorithm Retained {"))
        #expect(module.contains("} *)\nStateConstraint == (count < 2)\n===="))
        #expect(!module.contains("\\* StateConstraint"))
        #expect(spec.actions.contains(where: { $0.name == "stop" }))
    }

    @Test("renders authored module context around the Algorithm comment")
    func rendersAuthoredModuleContext() throws {
        let spec = TLASpec("Context") {
            Extends("Integers")
            Constant("N", 2)
            Definition("Seed == N")
            Symmetry("member", [1, 2] as Set<Int>)
            Algorithm("Context") {
                let count = SharedVar("count", initial: 0)
                count
                Do("stop") { Stop() }
                Invariant("Bounded") { count.expr <= 2 }
            }
        }

        let module = try spec.compile().renderedPlusCalBundle().root.tla

        #expect(module.contains("CONSTANTS N"))
        #expect(module.contains("TLC"))
        #expect(module.contains("Seed == N"))
        #expect(module.contains("(*--algorithm Context {"))
        #expect(module.contains("Bounded == (count <= 2)"))
        #expect(module.contains("Symmmember == Permutations({1, 2})"))
        let seed = try #require(module.range(of: "Seed == N"))
        let algorithm = try #require(module.range(of: "(*--algorithm Context {"))
        #expect(seed.lowerBound < algorithm.lowerBound)
    }
}
