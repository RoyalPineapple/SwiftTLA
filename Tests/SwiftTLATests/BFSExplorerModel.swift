import SwiftTLA

/// 1:1 port of Specifications/BFSExplorer/BFSExplorer.tla.
/// Uses set operations on Var<TLASetType> — now works inside Action closures
/// thanks to StateExprConvertible method forwarding.
///
/// MaxState=3, MaxExplore=2 keeps the state space finite and checkable.
/// Validate against TLC to prove DSL→TLA+ pipeline correctness.
public func createBFSExplorerSpec() -> TLASpec {
    let maxState = 3
    let states = StateExpr.set(Array(0..<maxState))

    let q        = Var<TLASetType>("q")
    let visited  = Var<TLASetType>("visited")
    let explored = Var<TLASetType>("explored")
    let ok       = Var<Bool>("ok")

    // Pre-build set expressions for each state node
    let nodeSets: [(source: Int, sourceSet: StateExpr, successorSet: StateExpr)] = (0..<maxState).compactMap { s in
        let next = s + 1
        guard next < maxState else { return nil }
        return (s, .setLiteral([.value(.int(s))]), .setLiteral([.value(.int(next))]))
    }

    return TLASpec("BFSExplorer") {
        Variable(q,       TLAValue.set([.int(0)]))
        Variable(visited, TLAValue.set([.int(0)]))
        Variable(explored,TLAValue.set([]))
        Variable(ok,      true)

        // q ≠ {} ∧ Cardinality(explored) < MaxExplore
        // LET s = CHOOSE x ∈ q : TRUE
        // IN q' = (q \ {s}) ∪ ({s+1} \ visited)
        //    visited' = visited ∪ {s+1}
        //    explored' = explored ∪ {s}
        //    ok' = ok
        for node in nodeSets {
            let sourceSet = node.sourceSet
            let successorSet = node.successorSet
            Action("process\(node.source)") {
                node.sourceSet.isIn(q)
                && explored.cardinality < 2
                && q.becomes(
                    q.subtracting(sourceSet)
                     .union(successorSet.subtracting(visited))
                )
                && visited.becomes(visited.union(successorSet))
                && explored.becomes(explored.union(sourceSet))
                && ok.stays
            }
        }

        Invariant("TypeOK") {
            q.isSubset(of: states)
            && visited.isSubset(of: states)
            && explored.isSubset(of: states)
            && explored.isSubset(of: visited)
        }

        Invariant("BoundOK") {
            explored.cardinality <= 2
        }
    }
}
