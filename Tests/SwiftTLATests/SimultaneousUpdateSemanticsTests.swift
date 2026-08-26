import Testing
@testable import SwiftTLA

@Suite("Simultaneous update semantics")
struct SimultaneousUpdateSemanticsTests {
    @Test("swap reads both right-hand sides from the old state")
    func swapUsesOldStateForEveryRightHandSide() throws {
        let left = Var<Int>("left")
        let right = Var<Int>("right")
        let spec = TLASpec("Swap") {
            Variable(left, 1)
            Variable(right, 2)
            Action("swap") {
                left.becomes(right)
                right.becomes(left)
            }
        }
        let compilation = try spec.compile()
        let initial = try firstCompiledState(in: compilation)

        let successor = try #require(try compiledSuccessors(named: "swap", arguments: [], in: compilation, from: initial).first)
        let verification = try ModelChecker(compilation: try spec.compile(), configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10, symmetryReduction: .disabled)).check()

        #expect(try renderedValue(named: "left", in: successor, compilation: compilation) == .int(2))
        #expect(try renderedValue(named: "right", in: successor, compilation: compilation) == .int(1))
        #expect(try renderedValue(named: "left", in: initial, compilation: compilation) == .int(1))
        #expect(try renderedValue(named: "right", in: initial, compilation: compilation) == .int(2))
        guard case .ok(let stateCount) = verification else {
            Issue.record("Expected the model checker to verify the two-state swap graph, found \(verification)")
            return
        }
        #expect(stateCount == 2)
    }

    @Test("aliased right-hand sides use one coherent pre-state")
    func aliasedRightHandSidesDoNotObserveEarlierAssignments() throws {
        let source = Var<Int>("source")
        let mirror = Var<Int>("mirror")
        let spec = TLASpec("AliasedUpdates") {
            Variable(source, 4)
            Variable(mirror, 0)
            Action("advance") {
                source.becomes(source + 1)
                mirror.becomes(source + 1)
            }
        }
        let compilation = try spec.compile()
        let initial = try firstCompiledState(in: compilation)

        let successor = try #require(try compiledSuccessors(named: "advance", arguments: [], in: compilation, from: initial).first)

        #expect(try renderedValue(named: "source", in: successor, compilation: compilation) == .int(5))
        #expect(try renderedValue(named: "mirror", in: successor, compilation: compilation) == .int(5))
        #expect(try renderedValue(named: "source", in: initial, compilation: compilation) == .int(4))
        #expect(try renderedValue(named: "mirror", in: initial, compilation: compilation) == .int(0))
    }

    @Test("an undefined right-hand side blocks compilation")
    func undefinedRightHandSideBlocksCompilation() {
        let left = Var<Int>("left")
        let right = Var<Int>("right")
        let spec = TLASpec("RejectedUpdate") {
            Variable(left, 1)
            Variable(right, 2)
            Action("reject") {
                left.becomes(left + 1)
                ActionExpr.assign(.named(right.name), .variable("missing"))
            }
        }
        do {
            _ = try spec.compile()
            Issue.record("Expected a binding diagnostic")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unknownReference)
            #expect(diagnostic.stage == .binding)
        } catch {
            Issue.record("Expected CompilationDiagnostic, got \(error)")
        }
    }
}
