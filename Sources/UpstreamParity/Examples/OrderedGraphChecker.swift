// The concrete checker uses sequences for its frontier and predecessor tree.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/TLC/TestGraphs.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct OrderedGraphChecker: Sendable {
    package enum Null: String, TLAValueType {
        case null
        package static var defaultValue: Self { .null }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package typealias Current = OneOf<Null,Int>
    package typealias Edge = Pair<Int,Int>
    private enum Step: String, CaseIterable { case scan = "init", finishScan = "initPost", dequeue = "scsr", visit = "each", trace = "trc", stop = "Terminating" }
    package static var spec: TLASpec {
        #spec("TestGraphs") { scope in
            let initials = scope.parameter(as: Set<Int>.self, in: Subsets(of: Int.all))
            let violations = scope.parameter(as: Set<Int>.self, in: Subsets(of: Int.all))
            let graph = scope.parameter(as: [Set<Int>].self, in: Sequences(of: Subsets(of: Int.all)))
            let witnesses = scope.parameter(as: SetExpr<[Int]>.self, in: Subsets(of: Sequences(of: Int.all)))
            let workers = scope.parameter(tlaName:"K", as:Int.self, in:Int.all)
            let pc = scope.sharedVar(initial:"init")
            let s = scope.sharedVar(tlaName:"S",initiallyIn:Sequences(of:initials,lengths:IntRange(initials.count,through:initials.count)).filter { perm in
                initials.allSatisfy { n in IntRange(1,through:perm.count).contains { i in perm[i] == n } }
            })
            let c = scope.sharedVar(tlaName:"C",initial:Set<Int>())
            let state = scope.sharedVar(initial:Current.first(Null.null))
            let successors = scope.sharedVar(initial:Set<Int>())
            let i = scope.sharedVar(initial:1)
            let counterexample = scope.sharedVar(initial:[Int]())
            let tree = scope.sharedVar(tlaName:"T",initial:[Edge]())
            let levels = scope.sharedVar(tlaName:"L",initial:Dictionary<Int,Int>())
            Do(Step.scan,when:pc == "init") {
                If(i <= s.count) {
                    Let(s[i]) { node in
                        state.set(Current.second(node)); c.insert(node)
                        levels.set(Dictionary<Int,Int>.mapping(over:levels.keys.inserting(node)) { k in If(k == node,then:0,else:levels[k]) })
                        i += 1
                        If(violations.contains(node)) { counterexample.set([Int]().appending(node)); pc.set("trc") }
                    }
                } else: { pc.set("initPost") }
            }
            Do(Step.finishScan,when:pc == "initPost") {
                Assert(c == IntRange(1,through:s.count).mapping { j in s[j] })
                pc.set("scsr")
            }
            Do(Step.dequeue,when:pc == "scsr") {
                If(s.isEmpty) { Assert(s.isEmpty); pc.set("Done") } else: {
                    With(IntRange(1,through:If(workers <= s.count,then:workers,else:s.count))) { index in
                        Let(s[index]) { node in
                            state.set(Current.second(node)); s.set(s.removing(at:index))
                            successors.set(graph[node].removing(node).subtracting(c))
                            If(graph[node].removing(node).isEmpty) { counterexample.set([Int]().appending(node)); pc.set("trc") }
                            else: { pc.set("each") }
                        }
                    }
                }
            }
            Do(Step.visit,when:pc == "each") {
                If(successors.isEmpty) { pc.set("scsr") } else: {
                    With(successors) { node in
                        let parent = state.assuming(Int.self)
                        successors.remove(node); c.insert(node); s.set(s.appending(node))
                        tree.set(tree.appending(Pair<Int,Int>.literal(parent,node)))
                        levels.set(Dictionary<Int,Int>.mapping(over:levels.keys.inserting(node)) { k in If(k == node,then:levels[parent]+1,else:levels[k]) })
                        If(violations.contains(node)) { counterexample.set([Int]().appending(parent).appending(node)); pc.set("trc") }
                    }
                }
            }
            Do(Step.trace,when:pc == "trc") {
                If(initials.contains(counterexample.head())) { Assert(!counterexample.isEmpty); pc.set("Done") }
                else: { counterexample.set(counterexample.prepending(tree.selecting { edge in edge.second() == counterexample.head() }.head().first())) }
            }
            Do(Step.stop,when:pc == "Done") { Skip() }
            WeakFairnessNext()
            Eventually("Termination",pc == "Done")
            let Live = Temporal()
            Live(.conditional(!violations.isEmpty,then:.eventuallyAlways(witnesses.contains(counterexample)
                && (workers != 1 || witnesses.allSatisfy { path in counterexample.count <= path.count })),else:.always(true)))
            let abstract = Instance(of:AbstractGraphChecker.self) {
                Bind(\.initials,to:initials); Bind(\.violations,to:violations); Bind(\.graph,to:graph)
            }
            let frontier = IntRange(1,through:s.count).mapping { j in s[j] }
            let pendingLevel = If(pc == "init" || pc == "initPost" || (pc == "scsr" && successors.isEmpty && c == frontier),
                then:0,else:levels[state.assuming(Int.self)]+1)
            let pending = successors.mapping { n in Triple<Int,Int,Int>.literal(pendingLevel,n,state.assuming(Int.self)) }
            let predecessors = IntRange(1,through:tree.count).mapping { j in tree[j] }
                .union(successors.mapping { n in Pair<Int,Int>.literal(state.assuming(Int.self),n) })
            Refinement("Refinement", instance:abstract) {
                Map(\.s,projecting:frontier); Map(\.c,from:c); Map(\.successors,projecting:pending)
                Map(\.done,projecting:!counterexample.isEmpty); Map(\.tree,projecting:predecessors)
                Map(\.counterexample,from:counterexample); Map(\.levels,from:levels)
            }
            Validation("Graph1") {
                Bind(initials,to:Set<Int>([1, 2]))
                Bind(violations,to:Set<Int>([4]))
                Bind(graph,to:[Set<Int>([1, 2]), Set<Int>([1, 3]), Set<Int>([4]), Set<Int>([3])])
                Bind(witnesses,to:SetExpr<[Int]>([2, 3, 4]))
                Bind(workers,to:1)
            }
            Validation("Graph1a") {
                Bind(initials,to:Set<Int>([3]))
                Bind(violations,to:Set<Int>([1]))
                Bind(graph,to:[Set<Int>([1, 2]), Set<Int>([1, 3]), Set<Int>([4]), Set<Int>([3])])
                Bind(witnesses,to:SetExpr<[Int]>())
                Bind(workers,to:1)
            }
            Validation("Graph2") {
                Bind(initials,to:Set<Int>([1, 3]))
                Bind(violations,to:Set<Int>([2, 5]))
                Bind(graph,to:[Set<Int>([1, 2]), Set<Int>([1]), Set<Int>([4, 5]), Set<Int>([]), Set<Int>([])])
                Bind(witnesses,to:SetExpr<[Int]>([1, 2], [3, 5]))
                Bind(workers,to:1)
            }
            Validation("Graph3") {
                Bind(initials,to:Set<Int>([2]))
                Bind(violations,to:Set<Int>([1]))
                Bind(graph,to:[Set<Int>([1, 2]), Set<Int>([2, 3]), Set<Int>([3, 4]), Set<Int>([1, 4])])
                Bind(witnesses,to:SetExpr<[Int]>([2, 3, 4, 1]))
                Bind(workers,to:1)
            }
            Validation("Graph4") {
                Bind(initials,to:Set<Int>([1, 2, 3]))
                Bind(violations,to:Set<Int>([8]))
                Bind(graph,to:[Set<Int>([3]), Set<Int>([4]), Set<Int>([5]), Set<Int>([6]), Set<Int>([7]), Set<Int>([7]), Set<Int>([8, 9]), Set<Int>([]), Set<Int>([4])])
                Bind(witnesses,to:SetExpr<[Int]>([3, 5, 7, 8], [2, 4, 6, 7, 8]))
                Bind(workers,to:1)
            }
            Validation("Graph5") {
                Bind(initials,to:Set<Int>([9]))
                Bind(violations,to:Set<Int>([8]))
                Bind(graph,to:[Set<Int>([4, 2]), Set<Int>([3]), Set<Int>([4]), Set<Int>([5]), Set<Int>([6]), Set<Int>([7]), Set<Int>([8]), Set<Int>([9]), Set<Int>([2])])
                Bind(witnesses,to:SetExpr<[Int]>([9, 2, 3, 4, 5, 6, 7, 8]))
                Bind(workers,to:1)
            }
            Validation("Graph6") {
                Bind(initials,to:Set<Int>([5]))
                Bind(violations,to:Set<Int>([2]))
                Bind(graph,to:[Set<Int>([2, 4, 5]), Set<Int>([2]), Set<Int>([1]), Set<Int>([4]), Set<Int>([3])])
                Bind(witnesses,to:SetExpr<[Int]>([5, 3, 1, 2]))
                Bind(workers,to:1)
            }
            Validation("Upstream") {
                Bind(initials,to:Set<Int>([1]))
                Bind(violations,to:Set<Int>([50]))
                Bind(graph,to:[Set<Int>([8, 35]), Set<Int>([15, 46, 22, 23, 50]), Set<Int>([20, 26, 34]), Set<Int>([5, 18, 28, 37, 43]), Set<Int>([18, 28]), Set<Int>([44]), Set<Int>([14, 29]), Set<Int>([42, 45]), Set<Int>([20, 49]), Set<Int>([10, 12, 31, 47]), Set<Int>([1, 8, 29, 30, 35, 42]), Set<Int>([22, 31]), Set<Int>([10, 12, 22, 27]), Set<Int>([23, 24, 48]), Set<Int>([9, 22, 49]), Set<Int>([9, 35, 50]), Set<Int>([10]), Set<Int>([21, 25, 39]), Set<Int>([7, 29, 33, 43]), Set<Int>([16, 41]), Set<Int>([]), Set<Int>([4, 36, 39, 47]), Set<Int>([7]), Set<Int>([12, 22, 23]), Set<Int>([5, 6, 39, 44]), Set<Int>([3, 35]), Set<Int>([10, 13, 17]), Set<Int>([6, 25, 33, 32, 43]), Set<Int>([23, 30, 40, 45]), Set<Int>([23, 50]), Set<Int>([24, 38]), Set<Int>([19, 33]), Set<Int>([6, 7, 14, 38, 48]), Set<Int>([3, 9, 20]), Set<Int>([3, 20, 41]), Set<Int>([10, 38, 47]), Set<Int>([21, 43]), Set<Int>([6, 10, 36, 48]), Set<Int>([36, 38, 39]), Set<Int>([19, 43]), Set<Int>([16]), Set<Int>([29, 45]), Set<Int>([32]), Set<Int>([38, 39]), Set<Int>([40]), Set<Int>([9, 15, 16, 50]), Set<Int>([17]), Set<Int>([24, 31]), Set<Int>([13, 22, 34]), Set<Int>([35, 23, 50])])
                Bind(witnesses,to:SetExpr<[Int]>([1, 35, 20, 16, 50], [1, 35, 41, 16, 50], [1, 8, 42, 29, 30, 50], [1, 8, 45, 40, 19, 29, 30, 50]))
                Bind(workers,to:1)
            }
            Validation("Graph8") {
                Bind(initials,to:Set<Int>([1]))
                Bind(violations,to:Set<Int>([]))
                Bind(graph,to:[Set<Int>([1, 2]), Set<Int>([2, 3]), Set<Int>([3, 4]), Set<Int>([4])])
                Bind(witnesses,to:SetExpr<[Int]>([1, 2, 3, 4]))
                Bind(workers,to:1)
            }
            Validation("Graph9") {
                Bind(initials,to:Set<Int>([1]))
                Bind(violations,to:Set<Int>([1]))
                Bind(graph,to:[Set<Int>([1])])
                Bind(witnesses,to:SetExpr<[Int]>([1]))
                Bind(workers,to:1)
            }
            Validation("Graph10") {
                Bind(initials,to:Set<Int>([]))
                Bind(violations,to:Set<Int>([]))
                Bind(graph,to:[])
                Bind(witnesses,to:SetExpr<[Int]>())
                Bind(workers,to:1)
            }
            Validation("Graph11") {
                Bind(initials,to:Set<Int>([]))
                Bind(violations,to:Set<Int>([]))
                Bind(graph,to:[Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([]), Set<Int>([])])
                Bind(witnesses,to:SetExpr<[Int]>())
                Bind(workers,to:1)
            }
            Validation("Graph12") {
                Bind(initials,to:Set<Int>([1, 2, 3]))
                Bind(violations,to:Set<Int>([1]))
                Bind(graph,to:[Set<Int>([]), Set<Int>([]), Set<Int>([])])
                Bind(witnesses,to:SetExpr<[Int]>([1]))
                Bind(workers,to:1)
            }
            Validation("Graph13") {
                Bind(initials,to:Set<Int>([1]))
                Bind(violations,to:Set<Int>([]))
                Bind(graph,to:[Set<Int>([2]), Set<Int>([3]), Set<Int>([])])
                Bind(witnesses,to:SetExpr<[Int]>([1, 2, 3]))
                Bind(workers,to:1)
            }
            Validation("GraphDH") {
                Bind(initials,to:Set<Int>([69]))
                Bind(violations,to:Set<Int>([28, 29, 30, 62, 63, 64, 83, 84, 93, 94]))
                Bind(graph,to:[Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([2, 16, 36, 50, 70, 86]), Set<Int>([3, 17, 37, 51, 70, 86]), Set<Int>([4, 18, 38, 52, 70, 86]), Set<Int>([5, 15, 39, 49, 71, 88]), Set<Int>([6, 16, 40, 50, 71, 88]), Set<Int>([7, 17, 41, 51, 71, 88]), Set<Int>([8, 15, 42, 49, 73, 90]), Set<Int>([9, 16, 43, 50, 73, 90]), Set<Int>([10, 17, 44, 51, 73, 90]), Set<Int>([11, 15, 45, 49, 75, 92]), Set<Int>([12, 16, 46, 50, 75, 92]), Set<Int>([13, 17, 47, 51, 75, 92]), Set<Int>([14, 18, 48, 52, 75, 92]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([2, 16, 36, 50, 70, 86]), Set<Int>([3, 17, 37, 51, 70, 86]), Set<Int>([4, 18, 38, 52, 70, 86]), Set<Int>([1, 19, 35, 53, 72, 87]), Set<Int>([2, 20, 36, 54, 72, 87]), Set<Int>([4, 21, 38, 55, 72, 87]), Set<Int>([1, 22, 35, 56, 74, 89]), Set<Int>([3, 23, 37, 57, 74, 89]), Set<Int>([4, 24, 38, 58, 74, 89]), Set<Int>([1, 25, 35, 59, 76, 91]), Set<Int>([3, 26, 37, 60, 76, 91]), Set<Int>([4, 27, 38, 61, 76, 91]), Set<Int>([1, 28, 35, 62, 78, 93]), Set<Int>([2, 29, 36, 63, 78, 93]), Set<Int>([4, 30, 38, 64, 78, 93]), Set<Int>([1, 31, 35, 65, 80, 95]), Set<Int>([2, 32, 36, 66, 80, 95]), Set<Int>([3, 33, 37, 67, 80, 95]), Set<Int>([4, 34, 38, 68, 80, 95]), Set<Int>([1, 31, 35, 65, 80, 95]), Set<Int>([2, 32, 36, 66, 80, 95]), Set<Int>([3, 33, 37, 67, 80, 95]), Set<Int>([4, 34, 38, 68, 80, 95]), Set<Int>([5, 31, 39, 65, 82, 97]), Set<Int>([6, 32, 40, 66, 82, 97]), Set<Int>([7, 33, 41, 67, 82, 97]), Set<Int>([8, 31, 42, 65, 84, 99]), Set<Int>([9, 32, 43, 66, 84, 99]), Set<Int>([10, 33, 44, 67, 84, 99]), Set<Int>([11, 31, 45, 65, 85, 101]), Set<Int>([12, 32, 46, 66, 85, 101]), Set<Int>([13, 33, 47, 67, 85, 101]), Set<Int>([14, 34, 48, 68, 85, 101]), Set<Int>([11, 15, 45, 49, 75, 92]), Set<Int>([12, 16, 46, 50, 75, 92]), Set<Int>([13, 17, 47, 51, 75, 92]), Set<Int>([14, 18, 48, 52, 75, 92]), Set<Int>([11, 19, 45, 53, 77, 94]), Set<Int>([12, 20, 46, 54, 77, 94]), Set<Int>([14, 21, 48, 55, 77, 94]), Set<Int>([11, 22, 45, 56, 79, 96]), Set<Int>([13, 23, 47, 57, 79, 96]), Set<Int>([14, 24, 48, 58, 79, 96]), Set<Int>([11, 25, 45, 59, 81, 98]), Set<Int>([13, 26, 47, 60, 81, 98]), Set<Int>([14, 27, 48, 61, 81, 98]), Set<Int>([11, 28, 45, 62, 83, 100]), Set<Int>([12, 29, 46, 63, 83, 100]), Set<Int>([14, 30, 48, 64, 83, 100]), Set<Int>([11, 31, 45, 65, 85, 101]), Set<Int>([12, 32, 46, 66, 85, 101]), Set<Int>([13, 33, 47, 67, 85, 101]), Set<Int>([14, 34, 48, 68, 85, 101]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([5, 15, 39, 49, 71, 88]), Set<Int>([6, 16, 40, 50, 71, 88]), Set<Int>([8, 15, 42, 49, 73, 90]), Set<Int>([10, 17, 44, 51, 73, 90]), Set<Int>([11, 15, 45, 49, 75, 92]), Set<Int>([14, 18, 48, 52, 75, 92]), Set<Int>([11, 19, 45, 53, 77, 94]), Set<Int>([14, 21, 48, 55, 77, 94]), Set<Int>([11, 22, 45, 56, 79, 96]), Set<Int>([14, 24, 48, 58, 79, 96]), Set<Int>([11, 25, 45, 59, 81, 98]), Set<Int>([13, 26, 47, 60, 81, 98]), Set<Int>([11, 28, 45, 62, 83, 100]), Set<Int>([12, 29, 46, 63, 83, 100]), Set<Int>([11, 31, 45, 65, 85, 101]), Set<Int>([1, 15, 35, 49, 70, 86]), Set<Int>([1, 19, 35, 53, 72, 87]), Set<Int>([2, 20, 36, 54, 72, 87]), Set<Int>([1, 22, 35, 56, 74, 89]), Set<Int>([3, 23, 37, 57, 74, 89]), Set<Int>([1, 25, 35, 59, 76, 91]), Set<Int>([4, 27, 38, 61, 76, 91]), Set<Int>([1, 28, 35, 62, 78, 93]), Set<Int>([4, 30, 38, 64, 78, 93]), Set<Int>([1, 31, 35, 65, 80, 95]), Set<Int>([4, 34, 38, 68, 80, 95]), Set<Int>([5, 31, 39, 65, 82, 97]), Set<Int>([7, 33, 41, 67, 82, 97]), Set<Int>([8, 31, 42, 65, 84, 99]), Set<Int>([9, 32, 43, 66, 84, 99]), Set<Int>([11, 31, 45, 65, 85, 101])])
                Bind(witnesses,to:SetExpr<[Int]>([69, 35, 31, 80, 24, 74, 10, 73, 42, 84], [69, 35, 31, 80, 24, 74, 44, 84], [69, 35, 31, 80, 24, 74, 73, 42, 84], [69, 35, 31, 80, 58, 24, 74, 44, 84], [69, 35, 31, 80, 58, 79, 22, 74, 44, 84], [69, 35, 31, 80, 58, 79, 22, 74, 73, 42, 84], [69, 35, 31, 80, 79, 22, 74, 44, 84], [69, 35, 65, 11, 92, 61, 98, 7, 88, 54, 94], [69, 35, 80, 24, 74, 44, 84], [69, 35, 80, 24, 74, 73, 42, 84], [69, 35, 80, 58, 79, 22, 74, 44, 84], [69, 35, 80, 79, 22, 74, 44, 84], [69, 49, 11, 92, 61, 98, 7, 88, 54, 94], [69, 49, 45, 31, 80, 24, 74, 44, 84], [69, 49, 92, 38, 80, 24, 74, 44, 84], [69, 49, 92, 61, 98, 41, 7, 88, 54, 94], [69, 49, 92, 61, 98, 7, 88, 54, 94]))
                Bind(workers,to:1)
            }
        }
    }
}
