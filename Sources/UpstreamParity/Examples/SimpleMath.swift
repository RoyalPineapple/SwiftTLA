// The module checks identities about finite sets by evaluating assumptions.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/SpecifyingSystems/SimpleMath/SimpleMath.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SimpleMathModel: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case a, b, c, d, e, f, g
        package static var defaultValue: Self { .a }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package typealias Member = OneOf<SetExpr<Atom>, Atom>

    package static var spec: TLASpec {
        #spec("SimpleMath") { scope in
            let a = scope.parameter(as: Atom.self, in: Set<Atom>([.a]))
            let b = scope.parameter(as: Atom.self, in: Set<Atom>([.b]))
            let c = scope.parameter(as: Atom.self, in: Set<Atom>([.c]))
            let d = scope.parameter(as: Atom.self, in: Set<Atom>([.d]))
            let e = scope.parameter(as: Atom.self, in: Set<Atom>([.e]))
            let f = scope.parameter(as: Atom.self, in: Set<Atom>([.f]))
            let g = scope.parameter(as: Atom.self, in: Set<Atom>([.g]))
            let truth = SetExpr<Bool>.literal(true, false)
            Assume(truth.allSatisfy { p in truth.allSatisfy { q in
                If(p, then: q, else: true) == (!p || q)
            } })
            Assume(!truth.allSatisfy { p in truth.allSatisfy { q in
                If(p || q, then: p && q, else: true)
            } })
            Assume(SetExpr<Int>.literal(1, 2, 2, 3, 3, 3) == SetExpr<Int>.literal(3, 1, 1, 2))
            Assume(SetExpr<Int>.literal(1, 2).union(SetExpr<Int>.literal(2, 3, 4))
                == SetExpr<Int>.literal(5, 4, 3, 2, 1).intersection(SetExpr<Int>.literal(1, 2, 3, 4)))
            Assume(SetExpr<Int>.literal(1, 3).isSubset(of: SetExpr<Int>.literal(3, 2, 1)))
            let ab = SetExpr<Atom>.literal(a, b)
            Assume(SetExpr<Atom>.literal(a, b, c).subtracting(SetExpr<Atom>.literal(c)) == ab)
            let de = SetExpr<Atom>.literal(d, e)
            let sets = SetExpr<SetExpr<Atom>>.literal(ab, de).mapping { member in Member.first(member) }
            let atoms = SetExpr<Atom>.literal(c).mapping { member in Member.second(member) }
            Assume(sets.union(atoms).contains(Member.first(ab)))
            let someSets = Subsets(of: SetExpr<Atom>.literal(a, b, c, d, e))
            Assume(someSets.allSatisfy { s in someSets.allSatisfy { t in
                s.isSubset(of: t) == (s == s.intersection(t))
            } })
            Validation("Upstream") {
                Bind(a, to: Atom.a)
                Bind(b, to: Atom.b)
                Bind(c, to: Atom.c)
                Bind(d, to: Atom.d)
                Bind(e, to: Atom.e)
                Bind(f, to: Atom.f)
                Bind(g, to: Atom.g)
            }.checkingDeadlock(false)
        }
    }
}
