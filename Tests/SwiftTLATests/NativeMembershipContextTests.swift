import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct NominalMembershipDomain {
    enum Value: String, CaseIterable, FiniteTLAValueDomain {
        case first, second
        static var defaultValue: Self { .first }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }
    static var spec: TLASpec {
        TLASpec("NominalMembershipDomain") {
            let entries = Var<Function<Int, SetExpr<Pair<Int, Value>>>>("entries")
            let found = Var<Bool>("found")
            Variable(entries, Expr<Function<Int, SetExpr<Pair<Int, Value>>>>(StateExpr.functionLiteral(
                StateExpr.set([0]), "key", SetExpr<Pair<Int, Value>>.literal(Pair<Int, Value>.literal(1, Value.first)).raw
            )))
            Variable(found, false)
            SwiftTLA.Action("lookup") {
                found.becomes(Expr<Bool>(Expr<SetExpr<Pair<Int, Value>>>(entries.stateExpr.applying(0)).contains(
                    Pair<Int, Value>.literal(1, Value.first)
                )))
            }
        }
    }
}

@Suite("Membership preserves the domain's native element representation")
struct NativeMembershipContextTests {
    @Test("A tuple candidate acquires its stored set's enum field type")
    func candidateUsesNominalDomainContext() throws {
        let compilation = try NominalMembershipDomain.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let lookup = try #require(compilation.layout.testActionID(named: "lookup"))
        let found = try #require(compilation.layout.testVariableID(named: "found"))
        let successor = try #require(try runtime.successors(for: lookup, from: initial).first)
        var machine = try NominalMembershipDomain.makeMachine()
        _ = try machine.send(.lookup)
        #expect(machine.state.found)
        #expect(try successor.state.value(for: found) == .boolean(machine.state.found))
    }

    @Test("A literal membership domain acquires its projected candidate's enum type")
    func literalDomainUsesProjectedCandidateContext() throws {
        let compilation = try TLASpec(
            name: "ProjectedNominalMember",
            variables: [.init(name: "entry", initialization: .value(.tuple([.int(1), .string("first")])), generatedSwiftType: "Pair<Int, Value>", origin: .compiler)],
            actions: [], invariants: [],
            constraint: .in(.tupleAccess(.variable("entry"), 2), .setLiteral([.string("first"), .string("second")]))
        ).compile()
        let plan = NativeMachinePlan(compilation: compilation)
        let evidence = try NativeTypeInference(plan: plan, sourceTypes: .init(enums: ["Value": [.string("first"), .string("second")]]))
        #expect(evidence.variables[plan.variables[0].id] == .tuple([.int, .named("Value")]))
        let constraint = try #require(plan.constraint)
        guard case .in(let candidate, let domain) = constraint else {
            Issue.record("Expected membership constraint")
            return
        }
        #expect(try evidence.membershipElementType(value: candidate, domain: domain) == .named("Value"))
    }

    @Test("Membership context rejects a literal outside its declared enum domain")
    func candidateCannotInventEnumMember() throws {
        let compilation = try TLASpec(
            name: "InvalidNominalMember",
            variables: [.init(name: "entries", initialization: .value(.set([])), generatedSwiftType: "SetExpr<Pair<Int, Value>>", origin: .compiler)],
            actions: [], invariants: [],
            constraint: .in(.tupleLiteral([.int(1), .string("other")]), .variable("entries"))
        ).compile()
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(plan: .init(compilation: compilation), sourceTypes: .init(enums: ["Value": [.string("first"), .string("second")]]))
        }
    }
}
