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

        let rendered = try algorithm.renderPlusCalModule()

        #expect(rendered.contains("---- MODULE RenderedProcess ----"))
        #expect(rendered.contains("count = 0"))
        #expect(rendered.contains("sentinel = \"__pcal_self\""))
        #expect(rendered.contains("(*--algorithm Rendered Process {"))
        #expect(rendered.contains("fair+ process (pcalProcess1 \\in {\"left\", \"right\"})"))
        #expect(rendered.contains("local = 0"))
        #expect(rendered.contains("repeat: while ((count < 2)) {"))
        #expect(rendered.contains("await (count >= 0);"))
        #expect(rendered.contains("assert (count < 3);"))
        #expect(rendered.contains("with (x1 \\in {1, 2})"))
        #expect(rendered.contains("with (x2 \\in {3, 4})"))
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

        let rendered = try algorithm.renderPlusCalModule()

        #expect(rendered.contains("EXTENDS Naturals, Integers, Sequences, FiniteSets"))
        #expect(rendered.contains("previous = -1"))
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
                    statements: [.set(.root("pcalProcess1"), .variable("__pcal_self"))]
                )]
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

        let rendered = try algorithm.renderPlusCalModule()

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
                    [.operator(.lambda(.init(parameters: ["value"], body: .variable("value")))]
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

        let modules = try spec.renderAuthoredPlusCalModules()

        #expect(modules.count == 1)
        #expect(modules[0].contains("(*--algorithm Retained {"))
        #expect(modules[0].contains("} *)\nStateConstraint == (count < 2)\n===="))
        #expect(!modules[0].contains("\\* StateConstraint"))
        #expect(spec.actions.contains(where: { $0.name == "stop" }))
    }
}
