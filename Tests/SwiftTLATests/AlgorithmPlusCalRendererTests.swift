import Testing
@testable import SwiftTLA

@Suite("PlusCal Algorithm renderer")
struct AlgorithmPlusCalRendererTests {
    private enum Node: String, FiniteDomainKey {
        case left
        case right
    }

    @Test("renders process declarations, source labels, and structured statements without lowering")
    func rendersProcessAlgorithm() throws {
        let algorithm = Algorithm("Rendered Process") {
            let count = SharedVar("count", initial: 0)
            let flags = SharedVar("flags", initial: Function<Node, Bool>.literal((.left, false), (.right, false)))
            count
            flags
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
                        Assign(flags[node], to: true)
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
        #expect(rendered.contains("fair+ process (self \\in {\"left\", \"right\"})"))
        #expect(rendered.contains("local = 0"))
        #expect(rendered.contains("repeat: while ((count < 2)) {"))
        #expect(rendered.contains("await (count >= 0);"))
        #expect(rendered.contains("assert (count < 3);"))
        #expect(rendered.contains("with (x1 \\in {1, 2})"))
        #expect(rendered.contains("with (x2 \\in {3, 4})"))
        #expect(rendered.contains("flags[self] := TRUE;"))
        #expect(rendered.contains("either {"))
        #expect(rendered.contains("goto repeat;"))
        #expect(rendered.contains("stop;"))
        #expect(rendered.contains("end algorithm;*)"))
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
        #expect(rendered.contains("begin\n  start:"))
    }

    @Test("reports source nodes that have no direct PlusCal spelling")
    func reportsUnsupportedSourceNode() {
        let model = AlgorithmModel(name: "Unsupported", components: [.propertyBoundary])

        #expect(throws: AlgorithmPlusCalRenderDiagnostic.self) {
            try AlgorithmPlusCalRenderer(model: model).render()
        }
    }
}
