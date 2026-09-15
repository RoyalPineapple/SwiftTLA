@testable import SwiftTLA
import Testing

struct SymmetryDomainAdmissionTests {
    @Test("Composite domains are rejected before distinct function keys can collide")
    func compositeMembersCannotCollapseDistinctFunctionKeys() {
        let atom = TLAValue.int(1)
        let composite = TLAValue.tuple([atom])
        let nested = TLAValue.tuple([composite])
        let spec = TLASpec(
            name: "CompositeDomainAdmission",
            variables: [.init(name: "function", initialization: .value(.function([atom: .int(0), nested: .int(1)])), origin: .compiler)],
            actions: [], invariants: [],
            symmetrySets: [.init(variableName: "Members", values: [atom, composite])]
        )
        expectInvalidCompositeDomain(spec)
    }

    @Test("Every composite member kind is rejected even in singleton domains")
    func declaredMembersMustBeAtomic() {
        let composites: [TLAValue] = [.tuple([]), .set([]), .record([:]), .function([:])]
        for member in composites {
            expectInvalidCompositeDomain(canonicalTestSpec(
                symmetrySets: [.init(variableName: "Members", values: [member])]
            ))
        }
    }

    @Test("All supported atomic member kinds retain idempotent representatives")
    func atomicDomainsRemainSupported() throws {
        let compilation = try TLASpec(
            name: "AtomicDomainPermutation",
            variables: [.init(name: "value", initialization: .value(.tuple([.int(2), .string("b")])), origin: .compiler)],
            actions: [], invariants: [],
            symmetrySets: [
                .init(variableName: "Numbers", values: [.int(1), .int(2)]),
                .init(variableName: "Names", values: [.string("a"), .string("b")]),
                .init(variableName: "Flags", values: [.bool(false), .bool(true)]),
                .init(variableName: "Models", values: [.constant("p"), .constant("q")])
            ]
        ).compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let plan = try SymmetryPlan(compilation: compilation, reduction: .enabled(maximumPermutationCount: 16))
        let initial = try #require(try runtime.initialStates().first)
        let canonical = try plan.canonicalState(initial)
        #expect(try plan.canonicalState(canonical) == canonical)
        let renamed = try CompiledState(values: [.tuple([.integer(1), .string("a")])], layout: compilation.layout, identity: compilation.identity)
        #expect(try plan.canonicalState(renamed) == canonical)
    }

    private func expectInvalidCompositeDomain(_ spec: TLASpec) {
        do {
            _ = try spec.compile()
            Issue.record("A composite symmetry domain compiled")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidSymmetryDeclaration)
            #expect(diagnostic.actual.contains("composite symmetry member"))
        } catch {
            Issue.record("Unexpected compilation error: \(error)")
        }
    }
}
