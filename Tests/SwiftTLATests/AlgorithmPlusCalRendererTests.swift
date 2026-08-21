import Testing
@testable import SwiftTLA

@Suite("PlusCal Algorithm renderer")
struct AlgorithmPlusCalRendererTests {
    private enum ProcessStep: String, PlusCalLabel, CaseIterable {
        case `repeat`
        case done
    }

    private enum ProcedureStep: String, PlusCalLabel, CaseIterable {
        case enter
        case start
        case finished
    }

    private enum Node: String, FiniteDomainKey {
        case left
        case right

        static var defaultValue: Self { .left }
        static let formalDomain: [Node] = [.left, .right]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.pluscal-renderer.node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    @Test("rejects residual anonymous formal lambdas")
    func rejectsResidualAnonymousFormalLambdas() {
        #expect(StateExpr.plusCalExpression(from: .variable("count"), using: { $0 }) != nil)
        #expect(StateExpr.plusCalExpression(from: .operatorApplication(
            .lambda(.init(parameters: ["value"], body: .variable("value"))),
            [.value(0)]
        ), using: { $0 }) != nil)
        #expect(StateExpr.plusCalExpression(from: .foldFunction(
            .init(parameters: ["left", "right"], body: .add(.variable("left"), .variable("right"))),
            initial: 0,
            sequence: .tupleLiteral([])
        ), using: { $0 }) == nil)
    }

    @Test("renders process declarations, source labels, and structured statements")
    func rendersProcessAlgorithm() throws {
        let algorithm = Algorithm("RenderedProcess") {
            let count = SharedVar("count", initial: 0)
            let flags = SharedVar("flags", initial: Function<Node, Bool>.literal((.left, false), (.right, false)))
            let sentinel = SharedVar("sentinel", initial: "author text")
            count
            flags
            sentinel
            Each(Node.all, fairness: .strong) { node in
                let local = LocalVar("local", initial: 0)
                local
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
            }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("---- MODULE RenderedProcess ----"))
        #expect(rendered.contains("count = 0"))
        #expect(rendered.contains("sentinel = \"author text\""))
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

    @Test("compilation prepares process identifiers for PlusCal")
    func preparesProcessIdentifiers() throws {
        let algorithm = Algorithm("ProcessIdentifier") {
            let flags = SharedVar("flags", initial: Function<Node, Bool>.literal((.left, false), (.right, false)))
            flags
            Each(Node.all) { node in
                Do(ProcessStep.done) {
                    Assign(flags, to: flags.updating(node, to: true))
                    Stop()
                }
            }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("flags := [flags EXCEPT ![self] = TRUE];"))
    }

    @Test("imports Integers when rendering a negative formal value")
    func rendersNegativeFormalValue() throws {
        let algorithm = Algorithm("Negative") {
            let previous = SharedVar("previous", initial: -1)
            previous
            Do(TestControlLabel.stop) { Stop() }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("EXTENDS Naturals, Integers, Sequences, FiniteSets"))
        #expect(rendered.contains("previous = -1"))
    }

    @Test("keeps prelude helpers outside and state helpers inside define")
    func rendersStructuredDeclarationSections() throws {
        let spec = TLASpec("Sections") {
            FormalDefinition("Bound", parameters: [], body: .value(.int(2)))
            Algorithm("Sections") {
                let count = SharedVar("count", initial: 0)
                count
                FormalDefinition(
                    "UsesCount",
                    parameters: [],
                    body: count.expr == 0,
                    plusCalPhase: .define
                )
                Do(TestControlLabel.done) { Stop() }
            }
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
        let algorithm = Algorithm("DirectSections") {
            let count = SharedVar("count", initial: 0)
            count
            FormalDefinition("Ready", taking: Int.self, plusCalPhase: .define) { _ in
                count == 0
            }
            Do(TestControlLabel.done) { Stop() }
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
        let spec = TLASpec("CompilerProperty") {
            Algorithm("Counter") {
                let count = SharedVar("count", initial: 0)
                count
                Do(TestControlLabel.done) { Stop() }
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

    @Test("renders a sequential body and procedures")
    func rendersSequentialProcedureAlgorithm() throws {
        let algorithm = Algorithm("Procedures") {
            let output = SharedVar("output", initial: 0)
            output
            Procedure("work", parameters: Int.self) { value in
                let offset = LocalVar("offset", initial: 1)
                offset
                Do(ProcedureStep.enter) {
                    Assign(output, to: value.expr + offset.expr)
                    Return()
                }
            }
            Do(ProcedureStep.start) { Call("work", with: 7) }
            Do(ProcedureStep.finished) { Stop() }
        }

        let rendered = try renderedSourceAlgorithmPlusCal(algorithm)

        #expect(rendered.contains("procedure work(parameter0)"))
        #expect(rendered.contains("enter:"))
        #expect(rendered.contains("output := (parameter0 + offset);"))
        #expect(rendered.contains("call work(7);"))
        #expect(rendered.contains("{\n  start:"))
    }

    @Test("retains authored Algorithm source for independent PlusCal rendering")
    func retainsAuthoredAlgorithmOnTheLoweredSpec() throws {
        let spec = TLASpec("Retained") {
            Algorithm("Retained") {
                let count = SharedVar("count", initial: 0)
                count
                Do(TestControlLabel.stop) { Stop() }
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
            Extends(.integers)
            Constant("N", 2)
            FormalDefinition("Seed", parameters: [], body: .variable("N"))
            Symmetry("member", [1, 2] as Set<Int>)
            Algorithm("Context") {
                let count = SharedVar("count", initial: 0)
                count
                Do(TestControlLabel.stop) { Stop() }
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

    @Test("standard module declarations preserve canonical order")
    func standardModuleDeclarationsPreserveCanonicalOrder() throws {
        let spec = TLASpec("Modules") {
            Extends(.naturals)
            Extends(.finiteSets)
            Algorithm("Modules") {
                let count = SharedVar("count", initial: 0)
                count
                Do(TestControlLabel.stop) { Stop() }
            }
        }

        #expect(spec.extendsModules == [.integers, .naturals, .finiteSets])
        #expect(try spec.compile().renderedPlusCalBundle().root.tla.contains(
            "EXTENDS Integers, Naturals, FiniteSets, Sequences"
        ))
    }
}
