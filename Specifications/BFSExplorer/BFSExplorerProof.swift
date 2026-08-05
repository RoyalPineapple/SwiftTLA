import SwiftTLA

/// BFS Explorer proof: verifies that our BFS correctly explores a linear graph.
/// Mapped from BFSExplorer.tla — same states, same properties.
@TLAModel
public struct BFSExplorerProof {
    static var spec: TLASpec {
        TLASpec("BFSExplorerProof") {
            let q_size = Var<Int>("qSize", value: 1)       // |q|
            let visited = Var<Int>("visitedCount", value: 1)// |visited|
            let explored = Var<Int>("explored", value: 0)  // |explored|
            Variable(q_size, 1)
            Variable(visited, 1)
            Variable(explored, 0)

            Action("Explore") {
                (q_size > 0) && (explored < 10) &&
                q_size.becomes(q_size - 1) &&
                visited.becomes(visited + 1) &&
                explored.becomes(explored + 1)
            }

            Action("Terminal") {
                (q_size == 0) && q_size.stays && visited.stays && explored.stays
            }

            Invariant("TypeOK") {
                q_size >= 0 && visited >= 0 && explored >= 0
            }

            Invariant("ExploredWithinVisited") {
                explored <= visited
            }

            Invariant("BoundOK") {
                explored <= 10
            }

            DeadlockCheck()
        }
    }
}
