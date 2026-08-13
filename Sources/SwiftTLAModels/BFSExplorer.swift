import SwiftTLA

/// Finite BFS explorer model (CHOOSE binding). MaxState=3, MaxExplore=2.
/// Spec-only (not `@TLAModel`) — set/choose surface is built at runtime.
public enum BFSExplorer {
    public static var spec: TLASpec {
        let maxState = 3
        let maxExplore = 2
        let statesSet = StateExpr.set(Array(0..<maxState))

        let q = Var<TLAValue>("q")
        let visited = Var<TLAValue>("visited")
        let explored = Var<TLAValue>("explored")
        let ok = Var<Bool>("ok")
        let picked = Var<Int>("picked")

        return TLASpec("BFSExplorer") {
            Variable(q, TLAValue.set([.int(0)]))
            Variable(visited, TLAValue.set([.int(0)]))
            Variable(explored, TLAValue.set([]))
            Variable(ok, true)
            Variable(picked, 0)

            Action("process") {
                q.stateExpr.cardinality > 0
                    && explored.stateExpr.cardinality < maxExplore
                    && choose(picked, from: q)
                    && q.becomes(Expr(.union(
                        StateExpr.setDifference(q.stateExpr, StateExpr.singleton(picked.stateExpr)),
                        StateExpr.setDifference(
                            StateExpr.singleton(StateExpr.add(picked.stateExpr, .int(1))),
                            visited.stateExpr))))
                    && visited.becomes(Expr(.union(visited.stateExpr, StateExpr.singleton(StateExpr.add(picked.stateExpr, .int(1))))))
                    && explored.becomes(Expr(.union(explored.stateExpr, StateExpr.singleton(picked.stateExpr))))
                    && ok.stays
            }

            Invariant("TypeOK") {
                q.stateExpr.isSubset(of: statesSet)
                    && visited.stateExpr.isSubset(of: statesSet)
                    && explored.stateExpr.isSubset(of: statesSet)
                    && explored.stateExpr.isSubset(of: visited.stateExpr)
            }

            Invariant("BoundOK") {
                explored.stateExpr.cardinality <= maxExplore
            }
        }
    }
}
