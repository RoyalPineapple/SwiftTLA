@testable import SwiftTLA
import Testing

struct SymmetryDomainAdmissionTests {
    private struct CollidingMember: Hashable, TLAValueConvertible {
        let id: Int
        var tlaValue: TLAValue { .string("same") }
    }

    @Test("Distinct Swift symmetry members cannot collapse to one formal value")
    func distinctSwiftMembersKeepTheirIdentity() {
        let members: Set<CollidingMember> = [.init(id: 1), .init(id: 2)]
        let spec = TLASpec("CollidingSymmetry") { Symmetry("Members", members) }
        do {
            _ = try spec.compile()
            Issue.record("Distinct Swift symmetry members collapsed")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .invalidSymmetryDeclaration)
            #expect(diagnostic.actual.contains("distinct Swift members have the same formal value"))
        } catch {
            Issue.record("Unexpected compilation error: \(error)")
        }
    }

    @Test("Symmetry accepts nonempty subsets of a finite set parameter")
    func parameterDependentMembersRemainFinite() throws {
        let spec = TLASpec("DependentSymmetry") { scope in
            let candidates = scope.parameter(as: Set<Int>.self,
                in: NonEmptySubsets(of: Set<Int>([1, 2])), _name: "candidates")
            let members = scope.parameter(as: Set<Int>.self,
                in: NonEmptySubsets(of: candidates), _name: "members")
            Symmetry(_name: "Members", members)
        }
        _ = try spec.compile()
    }

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

    @Test("Configured symmetry cannot bypass nonempty atomic member admission")
    func configuredMembersMustBeNonemptyAndAtomic() {
        let empty = TLASpec("EmptyConfiguredSymmetry") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set<Int>()]))
            Symmetry(_name: "Members", members)
        }
        let composite = TLASpec("CompositeConfiguredSymmetry") { scope in
            let members = scope.parameter(as: Set<[Int]>.self,
                in: Set<Set<[Int]>>([Set<[Int]>([[1], [2]])]))
            Symmetry(_name: "Members", members)
        }
        let subsetsIncludingEmpty = TLASpec("EmptySubsetSymmetry") { scope in
            let members = scope.parameter(as: Set<Int>.self,
                in: Subsets(of: Set<Int>([1, 2])))
            Symmetry(_name: "Members", members)
        }
        let compositeSubsets = TLASpec("CompositeSubsetSymmetry") { scope in
            let members = scope.parameter(as: Set<[Int]>.self,
                in: NonEmptySubsets(of: Set<[Int]>([[1], [2]])))
            Symmetry(_name: "Members", members)
        }
        let possiblyEmptySource = TLASpec("EmptyDependentSymmetry") { scope in
            let candidates = scope.parameter(as: Set<Int>.self,
                in: Subsets(of: Set<Int>([1, 2])), _name: "candidates")
            let members = scope.parameter(as: Set<Int>.self,
                in: NonEmptySubsets(of: candidates), _name: "members")
            Symmetry(_name: "Members", members)
        }
        for (spec, reason) in [(empty, "an empty domain"),
                               (composite, "composite symmetry member"),
                               (subsetsIncludingEmpty, "an empty domain"),
                               (possiblyEmptySource, "an empty domain"),
                               (compositeSubsets, "composite symmetry member")] {
            do {
                _ = try spec.compile()
                Issue.record("Invalid configured symmetry domain compiled")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.code == .invalidSymmetryDeclaration)
                #expect(diagnostic.path == "symmetrySets[0].values")
                #expect(diagnostic.actual.contains(reason))
            } catch {
                Issue.record("Unexpected compilation error: \(error)")
            }
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
