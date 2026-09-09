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
    enum Key: Int, CaseIterable, FiniteTLAValueDomain {
        case entry = 0
        static var defaultValue: Self { .entry }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .int(rawValue) }
    }
    enum Step: String, CaseIterable { case lookup }

    static var spec: TLASpec {
        #spec("NominalMembershipDomain") {
            Algorithm("NominalMembershipDomain") { scope in
                let entries = scope.sharedVar("entries", initial: Function<Key, SetExpr<Pair<Int, Value>>>.mapping { _ in
                    SetExpr<Pair<Int, Value>>.literal(Pair<Int, Value>.literal(1, Value.first))
                })
                let found = scope.sharedVar("found", initial: false)
                Do(Step.lookup) {
                    Assign(found, to: entries[Key.entry].contains(Pair<Int, Value>.literal(1, Value.first)))
                }
            }
        }
    }
}

@Suite("Membership preserves the domain's native element representation")
struct NativeMembershipContextTests {
    @Test("nested membership retains its Boolean type and rejects incompatible domains")
    func nestedMembership() throws {
        let specification = TLASpec(name: "NestedMembership", variables: [], actions: [], invariants: [])
        let checker = try NativeTypeInference(plan: .init(compilation: specification.compile()))
        let booleans = CompiledStateExpr.value(.set([.boolean(false), .boolean(true)]))
        let expression = (0..<12).reduce(CompiledStateExpr.value(.boolean(true))) { nested, _ in
            .in(nested, booleans)
        }
        #expect(try checker.type(of: expression) == .bool)
        #expect(throws: CompilationDiagnostic.self) {
            try checker.type(of: .in(expression, .value(.set([.integer(1)]))))
        }
    }

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
            constraint: .in(.tupleAccess(.variable("entry"), 2), .setLiteral([.value(.string("first")), .value(.string("second"))]))
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
            constraint: .in(.tupleLiteral([.int(1), .value(.string("other"))]), .variable("entries"))
        ).compile()
        #expect(throws: CompilationDiagnostic.self) {
            try NativeTypeInference(plan: .init(compilation: compilation), sourceTypes: .init(enums: ["Value": [.string("first"), .string("second")]]))
        }
    }
}
