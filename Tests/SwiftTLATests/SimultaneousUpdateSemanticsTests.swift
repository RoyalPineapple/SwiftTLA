import Testing
@testable import SwiftTLA

@Suite("Simultaneous update semantics")
struct SimultaneousUpdateSemanticsTests {
    private func value(_ name: String, in state: TLAStateProjection) throws -> TLAValue {
        guard let token = TLAStateProjection.Token(validating: name),
              let value = state.value(for: token) else {
            throw TLAStateProjectionDiagnostic.missingValue(path: name)
        }
        return value
    }

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
        let action = try #require(compilation.layout.actionID(named: "swap"))
        let initial = try #require(try compilation.initialStateProjections().first)

        let successor = try #require(try compilation.successors(for: action, arguments: [], from: initial).first)
        let verification = try ModelChecker(spec: spec, configuration: try FiniteExplorationConfiguration(maximumStateLimit: 10)).check()

        #expect(try value("left", in: successor) == .int(2))
        #expect(try value("right", in: successor) == .int(1))
        #expect(try value("left", in: initial) == .int(1))
        #expect(try value("right", in: initial) == .int(2))
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
        let compilation = try spec.compile()
        let action = try #require(compilation.layout.actionID(named: "advance"))
        let initial = try #require(try compilation.initialStateProjections().first)

        let successor = try #require(try compilation.successors(for: action, arguments: [], from: initial).first)

        #expect(try value("source", in: successor) == .int(5))
        #expect(try value("mirror", in: successor) == .int(5))
        #expect(try value("source", in: initial) == .int(4))
        #expect(try value("mirror", in: initial) == .int(0))
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
        let compilation = try spec.compile()
        let action = try #require(compilation.layout.actionID(named: "reject"))
        let initial = try TLAStateProjection(validating: [
            .init(token: try #require(TLAStateProjection.Token(validating: "left")), value: .int(1)),
            .init(token: try #require(TLAStateProjection.Token(validating: "right")), value: .int(2))
        ])
        do {
            _ = try compilation.successors(for: action, arguments: [], from: initial)
            Issue.record("Expected the undefined right-hand side to reject the transition")
        } catch let error as EvalError {
            guard case .undefinedVariable("missing") = error else {
                Issue.record("Expected the missing right-hand side, found \(error)")
                return
            }
        }
    }
}
