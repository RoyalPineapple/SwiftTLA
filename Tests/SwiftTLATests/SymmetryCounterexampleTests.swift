import Testing
import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct IdentitySensitiveSymmetryModel {
    enum Step: String, CaseIterable { case advance }
    enum Member: String, FiniteTLAValueDomain {
        case a, b
        static var defaultValue: Self { .a }
        static let finiteValues: [Self] = [.a, .b]
    }

    static var spec: TLASpec {
        #spec {
            let members = Symmetry(Set(Member.all))
            members
            let staysA = Invariant()
            let algorithm = Algorithm(scoped: { scope in
                let member = scope.sharedVar(initial: Member.a)
                Do(Step.advance) { Assign(member, to: Member.b) }
                staysA { member == Member.a }
            })
            algorithm
        }
    }
}

@Suite("symmetry must not hide counterexamples")
struct SymmetryCounterexampleTests {
    @Test("native checking retains identity-dependent states and the invariant counterexample")
    func retainsIdentityDependentViolation() throws {
        let graph = try ReachabilityGraph(
            initialMachines: IdentitySensitiveSymmetryModel.initialMachines(), maximumStates: 4,
            checking: .init(properties: [.staysA], checkDeadlock: false)
        )
        #expect(Set(graph.initialStates.map { $0.state.member }) == [.a])
        #expect(Set(graph.transitions.keys.map { $0.state.member }) == [.a, .b])
        let failure = try #require(graph.safetyViolations.first { $0.key.state.member == .b })
        #expect(failure.value == [.invariant(.staysA)])
        let trace = try graph.trace(to: failure.key)
        #expect(trace.map { $0.state.state.member } == [.a, .b])
        #expect(trace.last?.action == .advance)
    }
}
