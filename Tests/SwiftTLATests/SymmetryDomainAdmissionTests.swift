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
