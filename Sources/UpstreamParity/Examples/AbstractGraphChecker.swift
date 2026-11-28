// The abstract checker retains a set of pending (level, target, source) observations.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/TLC/TestMCReachability.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct AbstractGraphChecker: Sendable {
    package typealias Edge = Pair<Int,Int>
    package typealias Pending = Triple<Int,Int,Int>
    private enum Step: String, CaseIterable {
        case initial = "InitCheck", explore = "Explore", each = "Each", trace = "Trc", stop = "Terminating"
    }
    package static var spec: TLASpec {
        #spec("TestMCReachability") { scope in
            let initials = scope.parameter(as: Set<Int>.self, in: Subsets(of: Int.all))
            let violations = scope.parameter(as: Set<Int>.self, in: Subsets(of: Int.all))
            let graph = scope.parameter(as: [Set<Int>].self, in: Sequences(of: Subsets(of: Int.all)))
            let s = scope.sharedVar(tlaName: "S", initial: initials)
            let c = scope.sharedVar(tlaName: "C", initial: Set<Int>())
            let successors = scope.sharedVar(initial: Set<Pending>())
            let done = scope.sharedVar(initial: false)
            let tree = scope.sharedVar(tlaName: "T", initial: Set<Edge>())
            let counterexample = scope.sharedVar(initial: [Int]())
            let levels = scope.sharedVar(tlaName: "L", initial: Dictionary<Int,Int>())
            Do(Step.initial) {
                When(!done && successors.isEmpty)
                With(s.subtracting(c)) { node in
                    c.insert(node)
                    levels.set(Dictionary<Int,Int>.mapping(over: levels.keys.inserting(node)) { k in If(k == node, then: 0, else: levels[k]) })
                    done.set(violations.contains(node))
                    If(violations.contains(node)) { counterexample.set([Int]().appending(node)) }
                }
            }
            Do(Step.explore) {
                When(!done && successors.isEmpty && s.isSubset(of: c))
                With(s) { node in
                    let neighbors = graph[node].removing(node)
                    let fresh = neighbors.subtracting(c)
                    s.remove(node)
                    successors.set(fresh.mapping { target in Triple<Int,Int,Int>.literal(levels[node] + 1, target, node) })
                    tree.set(tree.union(fresh.mapping { target in Pair<Int,Int>.literal(node,target) }))
                    done.set(neighbors.isEmpty)
                    If(neighbors.isEmpty) { counterexample.set([Int]().appending(node)) }
                }
            }
            Do(Step.each) {
                When(!done)
                With(successors) { item in
                    let node = item.second()
                    successors.remove(item)
                    c.insert(node); s.insert(node)
                    levels.set(Dictionary<Int,Int>.mapping(over: levels.keys.inserting(node)) { k in If(k == node, then: item.first(), else: levels[k]) })
                    done.set(violations.contains(node))
                    If(violations.contains(node)) { counterexample.set([Int]().appending(item.third()).appending(node)) }
                }
            }
            Do(Step.trace) {
                When(done && !counterexample.isEmpty && !initials.contains(counterexample.head()))
                let parent = Select(from: tree) { e in e.second() == counterexample.head() }
                counterexample.set(counterexample.prepending(parent.first()))
            }
            Do(Step.stop, when: done) { Skip() }
            WeakFairnessNext()
            Eventually("Termination", done || (s.isEmpty && successors.isEmpty))
            let Live = Temporal()
            Live(.conditional(!violations.isEmpty, then: .eventuallyAlways(!counterexample.isEmpty
                && violations.contains(counterexample[counterexample.count]) && initials.contains(counterexample[1])), else: .always(true)))
            // A scenario per published GRAPH value; the default when GRAPH is absent is "7".
            Validation("Graph1") {
                Bind(initials, to: Set<Int>([1, 2]))
                Bind(violations, to: Set<Int>([4]))
                Bind(graph, to: [Set<Int>([1, 2]), Set<Int>([1, 3]), Set<Int>([4]), Set<Int>([3])])
            }
            Validation("Graph1a") {
                Bind(initials, to: Set<Int>([3]))
                Bind(violations, to: Set<Int>([1]))
                Bind(graph, to: [Set<Int>([1, 2]), Set<Int>([1, 3]), Set<Int>([4]), Set<Int>([3])])
            }
            Validation("Graph2") {
                Bind(initials, to: Set<Int>([1, 3]))
                Bind(violations, to: Set<Int>([2, 5]))
                Bind(graph, to: [Set<Int>([1, 2]), Set<Int>([1]), Set<Int>([4, 5]), Set<Int>([]), Set<Int>([])])
            }
            Validation("Graph3") {
                Bind(initials, to: Set<Int>([2]))
                Bind(violations, to: Set<Int>([1]))
                Bind(graph, to: [Set<Int>([1, 2]), Set<Int>([2, 3]), Set<Int>([3, 4]), Set<Int>([1, 4])])
            }
            Validation("Graph4") {
                Bind(initials, to: Set<Int>([1, 2, 3]))
                Bind(violations, to: Set<Int>([8]))
                Bind(graph, to: [Set<Int>([3]), Set<Int>([4]), Set<Int>([5]), Set<Int>([6]), Set<Int>([7]), Set<Int>([7]), Set<Int>([8, 9]), Set<Int>([]), Set<Int>([4])])
            }
            Validation("Graph5") {
                Bind(initials, to: Set<Int>([9]))
                Bind(violations, to: Set<Int>([8]))
                Bind(graph, to: [Set<Int>([4, 2]), Set<Int>([3]), Set<Int>([4]), Set<Int>([5]), Set<Int>([6]), Set<Int>([7]), Set<Int>([8]), Set<Int>([9]), Set<Int>([2])])
            }
            Validation("Graph6") {
                Bind(initials, to: Set<Int>([5]))
                Bind(violations, to: Set<Int>([2]))
                Bind(graph, to: [Set<Int>([2, 4, 5]), Set<Int>([2]), Set<Int>([1]), Set<Int>([4]), Set<Int>([3])])
            }
            Validation("Upstream") {
                Bind(initials, to: Set<Int>([1]))
                Bind(violations, to: Set<Int>([50]))
                Bind(graph, to: [Set<Int>([8, 35]), Set<Int>([15, 46, 22, 23, 50]), Set<Int>([20, 26, 34]), Set<Int>([5, 18, 28, 37, 43]), Set<Int>([18, 28]), Set<Int>([44]), Set<Int>([14, 29]), Set<Int>([42, 45]), Set<Int>([20, 49]), Set<Int>([10, 12, 31, 47]), Set<Int>([1, 8, 29, 30, 35, 42]), Set<Int>([22, 31]), Set<Int>([10, 12, 22, 27]), Set<Int>([23, 24, 48]), Set<Int>([9, 22, 49]), Set<Int>([9, 35, 50]), Set<Int>([10]), Set<Int>([21, 25, 39]), Set<Int>([7, 29, 33, 43]), Set<Int>([16, 41]), Set<Int>([]), Set<Int>([4, 36, 39, 47]), Set<Int>([7]), Set<Int>([12, 22, 23]), Set<Int>([5, 6, 39, 44]), Set<Int>([3, 35]), Set<Int>([10, 13, 17]), Set<Int>([6, 25, 33, 32, 43]), Set<Int>([23, 30, 40, 45]), Set<Int>([23, 50]), Set<Int>([24, 38]), Set<Int>([19, 33]), Set<Int>([6, 7, 14, 38, 48]), Set<Int>([3, 9, 20]), Set<Int>([3, 20, 41]), Set<Int>([10, 38, 47]), Set<Int>([21, 43]), Set<Int>([6, 10, 36, 48]), Set<Int>([36, 38, 39]), Set<Int>([19, 43]), Set<Int>([16]), Set<Int>([29, 45]), Set<Int>([32]), Set<Int>([38, 39]), Set<Int>([40]), Set<Int>([9, 15, 16, 50]), Set<Int>([17]), Set<Int>([24, 31]), Set<Int>([13, 22, 34]), Set<Int>([35, 23, 50])])
            }.expect(Live, .violated)
            Validation("Graph8") {
                Bind(initials, to: Set<Int>([1]))
                Bind(violations, to: Set<Int>([]))
                Bind(graph, to: [Set<Int>([1, 2]), Set<Int>([2, 3]), Set<Int>([3, 4]), Set<Int>([4])])
            }
            Validation("Graph9") {
                Bind(initials, to: Set<Int>([1]))
                Bind(violations, to: Set<Int>([1]))
                Bind(graph, to: [Set<Int>([1])])
            }
            Validation("Graph10") {
                Bind(initials, to: Set<Int>([]))
                Bind(violations, to: Set<Int>([]))
                Bind(graph, to: [])
            }
            Validation("Graph11") {
                Bind(initials, to: Set<Int>([]))
                Bind(violations, to: Set<Int>([]))
                Bind(graph, to: [Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([])])
            }
            Validation("Graph12") {
                Bind(initials, to: Set<Int>([1, 2, 3]))
                Bind(violations, to: Set<Int>([1]))
                Bind(graph, to: [Set<Int>([]), Set<Int>([]), Set<Int>([])])
            }
            Validation("Graph13") {
                Bind(initials, to: Set<Int>([1]))
                Bind(violations, to: Set<Int>([]))
                Bind(graph, to: [Set<Int>([2]), Set<Int>([3]), Set<Int>([])])
            }
            Validation("GraphDH") {
                Bind(initials, to: Set<Int>([69]))
                Bind(violations, to: Set<Int>([28, 29, 30, 62, 63, 64, 83, 84, 93, 94]))
                Bind(graph, to: [Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([2, 16, 36, 50, 70, 86]), Set<Int>([3, 17, 37, 51, 70, 86]), Set<Int>([4, 18, 38, 52, 70, 86]), Set<Int>([5, 15, 39, 49, 71, 88]), Set<Int>([6, 16, 40, 50, 71, 88]), Set<Int>([7, 17, 41, 51, 71, 88]), Set<Int>([8, 15, 42, 49, 73, 90]), Set<Int>([9, 16, 43, 50, 73, 90]), Set<Int>([10, 17, 44, 51, 73, 90]), Set<Int>([11, 15, 45, 49, 75, 92]), Set<Int>([12, 16, 46, 50, 75, 92]), Set<Int>([13, 17, 47, 51, 75, 92]), Set<Int>([14, 18, 48, 52, 75, 92]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([2, 16, 36, 50, 70, 86]), Set<Int>([3, 17, 37, 51, 70, 86]), Set<Int>([4, 18, 38, 52, 70, 86]), Set<Int>([1, 19, 35, 53, 72, 87]), Set<Int>([2, 20, 36, 54, 72, 87]), Set<Int>([4, 21, 38, 55, 72, 87]), Set<Int>([1, 22, 35, 56, 74, 89]), Set<Int>([3, 23, 37, 57, 74, 89]), Set<Int>([4, 24, 38, 58, 74, 89]), Set<Int>([1, 25, 35, 59, 76, 91]), Set<Int>([3, 26, 37, 60, 76, 91]), Set<Int>([4, 27, 38, 61, 76, 91]), Set<Int>([1, 28, 35, 62, 78, 93]), Set<Int>([2, 29, 36, 63, 78, 93]), Set<Int>([4, 30, 38, 64, 78, 93]), Set<Int>([1, 31, 35, 65, 80, 95]), Set<Int>([2, 32, 36, 66, 80, 95]), Set<Int>([3, 33, 37, 67, 80, 95]), Set<Int>([4, 34, 38, 68, 80, 95]), Set<Int>([1, 31, 35, 65, 80, 95]), Set<Int>([2, 32, 36, 66, 80, 95]), Set<Int>([3, 33, 37, 67, 80, 95]), Set<Int>([4, 34, 38, 68, 80, 95]), Set<Int>([5, 31, 39, 65, 82, 97]), Set<Int>([6, 32, 40, 66, 82, 97]), Set<Int>([7, 33, 41, 67, 82, 97]), Set<Int>([8, 31, 42, 65, 84, 99]), Set<Int>([9, 32, 43, 66, 84, 99]), Set<Int>([10, 33, 44, 67, 84, 99]), Set<Int>([11, 31, 45, 65, 85, 101]), Set<Int>([12, 32, 46, 66, 85, 101]), Set<Int>([13, 33, 47, 67, 85, 101]), Set<Int>([14, 34, 48, 68, 85, 101]), Set<Int>([11, 15, 45, 49, 75, 92]), Set<Int>([12, 16, 46, 50, 75, 92]), Set<Int>([13, 17, 47, 51, 75, 92]), Set<Int>([14, 18, 48, 52, 75, 92]), Set<Int>([11, 19, 45, 53, 77, 94]), Set<Int>([12, 20, 46, 54, 77, 94]), Set<Int>([14, 21, 48, 55, 77, 94]), Set<Int>([11, 22, 45, 56, 79, 96]), Set<Int>([13, 23, 47, 57, 79, 96]), Set<Int>([14, 24, 48, 58, 79, 96]), Set<Int>([11, 25, 45, 59, 81, 98]), Set<Int>([13, 26, 47, 60, 81, 98]), Set<Int>([14, 27, 48, 61, 81, 98]), Set<Int>([11, 28, 45, 62, 83, 100]), Set<Int>([12, 29, 46, 63, 83, 100]), Set<Int>([14, 30, 48, 64, 83, 100]), Set<Int>([11, 31, 45, 65, 85, 101]), Set<Int>([12, 32, 46, 66, 85, 101]), Set<Int>([13, 33, 47, 67, 85, 101]), Set<Int>([14, 34, 48, 68, 85, 101]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([5, 15, 39, 49, 71, 88]), Set<Int>([6, 16, 40, 50, 71, 88]), Set<Int>([8, 15, 42, 49, 73, 90]), Set<Int>([10, 17, 44, 51, 73, 90]), Set<Int>([11, 15, 45, 49, 75, 92]), Set<Int>([14, 18, 48, 52, 75, 92]), Set<Int>([11, 19, 45, 53, 77, 94]), Set<Int>([14, 21, 48, 55, 77, 94]), Set<Int>([11, 22, 45, 56, 79, 96]), Set<Int>([14, 24, 48, 58, 79, 96]), Set<Int>([11, 25, 45, 59, 81, 98]), Set<Int>([13, 26, 47, 60, 81, 98]), Set<Int>([11, 28, 45, 62, 83, 100]), Set<Int>([12, 29, 46, 63, 83, 100]), Set<Int>([11, 31, 45, 65, 85, 101]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([1, 19, 35, 53, 72, 87]), Set<Int>([2, 20, 36, 54, 72, 87]), Set<Int>([1, 22, 35, 56, 74, 89]), Set<Int>([3, 23, 37, 57, 74, 89]), Set<Int>([1, 25, 35, 59, 76, 91]), Set<Int>([4, 27, 38, 61, 76, 91]), Set<Int>([1, 28, 35, 62, 78, 93]), Set<Int>([4, 30, 38, 64, 78, 93]), Set<Int>([1, 31, 35, 65, 80, 95]), Set<Int>([4, 34, 38, 68, 80, 95]), Set<Int>([5, 31, 39, 65, 82, 97]), Set<Int>([7, 33, 41, 67, 82, 97]), Set<Int>([8, 31, 42, 65, 84, 99]), Set<Int>([9, 32, 43, 66, 84, 99]), Set<Int>([11, 31, 45, 65, 85, 101])])
            }
        }
    }
}
