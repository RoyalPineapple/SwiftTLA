import SwiftTLA

/// Finite BFS explorer model (CHOOSE binding). MaxState=3, MaxExplore=2.
/// Spec-only (not `@TLAModel`) — set/choose surface is built at runtime.
public enum BFSExplorer {
    public static var spec: TLASpec {
        let maxState = 3
        let maxExplore = 2
        let statesSet = StateExpr.set(Array(0..<maxState))

        let q = Var<TLASetType>("q")
        let visited = Var<TLASetType>("visited")
        let explored = Var<TLASetType>("explored")
        let ok = Var<Bool>("ok")
        let picked = Var<Int>("picked", value: 0)

        return TLASpec("BFSExplorer") {
            Variable(q, TLAValue.set([.int(0)]))
            Variable(visited, TLAValue.set([.int(0)]))
            Variable(explored, TLAValue.set([]))
            Variable(ok, true)
            Variable(picked, 0)

            Action("process") {
                q.cardinality > 0
                    && explored.cardinality < maxExplore
                    && choose(picked, from: q)
                    && q.becomes(Expr(.setDifference(
                        q.stateExpr,
                        StateExpr.union(StateExpr.singleton(picked.stateExpr),
                            StateExpr.singleton(StateExpr.add(picked.stateExpr, .int(1)))))))
                    && visited.becomes(Expr(.union(visited.stateExpr, StateExpr.singleton(StateExpr.add(picked.stateExpr, .int(1))))))
                    && explored.becomes(Expr(.union(explored.stateExpr, StateExpr.singleton(picked.stateExpr))))
                    && ok.stays
            }

            Invariant("TypeOK") {
                q.isSubset(of: statesSet)
                    && visited.isSubset(of: statesSet)
                    && explored.isSubset(of: statesSet)
                    && explored.isSubset(of: visited)
            }

            Invariant("BoundOK") {
                explored.cardinality <= maxExplore
            }
        }
    }
}
