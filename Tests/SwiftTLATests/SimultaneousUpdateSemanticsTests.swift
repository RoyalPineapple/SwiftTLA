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
        let runtime = try SpecRuntime(spec: spec)
        let initial = try #require(runtime.initialStates().first)

        let successor = try runtime.apply(.init(name: "swap"), to: initial)
        let verification = try ModelChecker(spec: spec, maxStates: 10).check()

        #expect(successor["left"] == .int(2))
        #expect(successor["right"] == .int(1))
        #expect(initial == ["left": .int(1), "right": .int(2)])
        guard case .ok(let stateCount) = verification.underlyingOutcome else {
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
        let runtime = try SpecRuntime(spec: spec)
        let initial = try #require(runtime.initialStates().first)

        let successor = try runtime.apply(.init(name: "advance"), to: initial)

        #expect(successor["source"] == .int(5))
        #expect(successor["mirror"] == .int(5))
        #expect(initial == ["source": .int(4), "mirror": .int(0)])
    }

    @Test("a failed later right-hand side does not partially commit a canonical machine")
    func failedRightHandSideLeavesCanonicalSnapshotUnchanged() throws {
        let left = Var<Int>("left")
        let right = Var<Int>("right")
        let spec = TLASpec("RejectedUpdate") {
            Variable(left, 1)
            Variable(right, 2)
            Action("reject") {
                left.becomes(left + 1)
                ActionExpr.assign(right.name, .variable("missing"))
            }
        }
        let runtime = try SpecRuntime(spec: spec)
        var machine = CanonicalMachine(
            runtime: runtime,
            initial: ["left": TLAValue.int(1), "right": .int(2)],
            stateDictionary: { $0 },
            snapshotFromDictionary: { $0 }
        )
        let before = machine.snapshot

        do {
            _ = try machine.apply(.init(name: "reject"))
            Issue.record("Expected the undefined right-hand side to reject the transition")
        } catch let GeneratedMachineError.runtime(error) {
            guard case .enumerationFailed(let requested, let evaluated, let underlying) = error else {
                Issue.record("Expected action evaluation evidence, found \(error)")
                return
            }
            #expect(requested == .init(name: "reject"))
            #expect(evaluated == .init(name: "reject"))
            guard case .some(.undefinedVariable("missing")) = underlying as? EvalError else {
                Issue.record("Expected the missing right-hand side, found \(underlying)")
                return
            }
        }

        #expect(machine.snapshot == before)
        let report = runtime.actionReport(named: "reject", in: before)
        #expect(report.stateCommitted == false)
        #expect(report.status == SpecRuntime.RuntimeActionReport.Status.evaluationFailed(.init(
            code: .evaluationError,
            message: "Undefined variable: missing"
        )))
    }
}
