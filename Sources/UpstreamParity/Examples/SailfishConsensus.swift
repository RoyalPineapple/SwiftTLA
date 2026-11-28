// Correct and faulty nodes add vertices to one block DAG. Both published configurations check the logs.
// https://github.com/tlaplus/Examples/tree/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/dag-consensus
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SailfishConsensus: Sendable {
    package enum Member: String, CaseIterable, FiniteTLAValueDomain {
        case n1, n2, n3, n4
        package static let finiteValues = allCases
        package static var defaultValue: Self { .n1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package typealias Coordinate = OneOf<Member,Int>
    package typealias Vertex = [Coordinate]
    package typealias Edge = Pair<Vertex,Vertex>
    private enum Step: String, CaseIterable { case correctNode, byzantineNode, terminate = "Terminate" }
    package static var spec: TLASpec {
        #spec("Sailfish") { scope in
            let domain = Set<Member>([.n1,.n2,.n3,.n4])
            let schedule = scope.parameter(as: [Member].self, in: Sequences(of: domain))
            let nodes = IntRange(1, through: schedule.count).mapping { i in schedule[i] }
            let correct = nodes.removing(Member.n1)
            let rounds = IntRange(1, through: 5)
            let gst = If(schedule.count == 3, then: 3, else: 6)
            let genesis = [Coordinate]()
            let vs = scope.sharedVar(initial: Set<Vertex>().inserting(genesis))
            let es = scope.sharedVar(initial: Set<Edge>())
            let round = scope.sharedVar(initial: Dictionary<Member,Int>.mapping(over: correct) { _ in 0 })
            let log = scope.sharedVar(initial: Dictionary<Member,[Vertex]>.mapping(over: correct) { _ in [Vertex]() })
            FormalDefinition("Round", taking: Vertex.self) { v -> Expr<Int> in
                If(v == genesis, then: 0, else: v[2].assuming(Int.self))
            }
            FormalDefinition("LeaderVertex", taking: Int.self) { r -> Expr<Vertex> in
                If(r > 0, then: Pair<Member, Int>.literal(schedule[(r-1) % schedule.count + 1], r).assuming(Vertex.self), else: genesis)
            }
            FormalDefinition("Children", taking: Vertex.self) { v -> Expr<Set<Vertex>> in
                es.filter { e in e.first() == v }.mapping { e in e.second() }
            }
            FormalDefinition("Quorum", taking: Set<Member>.self) { ids -> Expr<Bool> in
                If(schedule.count == 3, then: ids.contains(Member.n3) && ids.count >= 2, else: ids.count >= 3)
            }
            FormalDefinition("Ancestors", taking: Vertex.self) { root -> Expr<Set<Vertex>> in
                LetRec("Above", over: IntRange(0, through: 5), taking: Int.self, { above, k in
                    If(k == 0, then: Set<Vertex>().inserting(root), else: above(k-1).flatMapping { vertex in
                        FormalCall(as: Set<Vertex>.self, "Children", vertex).inserting(vertex)
                    })
                }, in: { above in above(5) })
            }
            FormalDefinition("ChosenVertex", taking: Set<Vertex>.self) { group -> Expr<Vertex> in
                Select(from: group) { _ in true }
            }
            FormalDefinition("OrderSet", taking: Set<Vertex>.self) { input -> Expr<[Vertex]> in
                LetRec("Order", over: Subsets(of: vs), taking: Set<Vertex>.self, { order, rest in
                    If(rest.isEmpty, then: [Vertex](), else: order(rest.removing(FormalCall(as: Vertex.self, "ChosenVertex", rest)))
                        .appending(FormalCall(as: Vertex.self, "ChosenVertex", rest)))
                }, in: { order in order(input) })
            }
            FormalDefinition("EarlierRounds", taking: Vertex.self) { v -> Expr<Set<Int>> in
                (0..<FormalCall(as: Int.self, "Round", v)).filter { k in
                    FormalCall(as: Set<Vertex>.self, "Ancestors", v).contains(FormalCall(as: Vertex.self, "LeaderVertex", k))
                }
            }
            FormalDefinition("Latest", taking: Set<Int>.self) { earlier -> Expr<Int> in
                Select(from: earlier) { k in earlier.allSatisfy { j in j <= k } }
            }
            FormalDefinition("PreviousLeader", taking: Vertex.self) { v -> Expr<Vertex> in
                FormalCall(as: Vertex.self, "LeaderVertex", FormalCall(as: Int.self, "Latest", FormalCall(as: Set<Int>.self, "EarlierRounds", v)))
            }
            FormalDefinition("Linearize", taking: Vertex.self) { root -> Expr<[Vertex]> in
                LetRec("Walk", over: vs, taking: Vertex.self, { walk, v in
                    If(v == genesis, then: [Vertex](), else: walk(FormalCall(as: Vertex.self, "PreviousLeader", v))
                        .concatenating(FormalCall(as: [Vertex].self, "OrderSet",
                            FormalCall(as: Set<Vertex>.self, "Ancestors", v).subtracting(FormalCall(as: Set<Vertex>.self, "Ancestors",
                                FormalCall(as: Vertex.self, "PreviousLeader", v))).removing(v))).appending(v))
                }, in: { walk in walk(root) })
            }
            Do(Step.correctNode, over: correct) { node in
                If(round[node] == 0) {
                    let v = Pair<Member, Int>.literal(node, 1).assuming(Vertex.self)
                    vs.insert(v); es.insert(Pair<Vertex,Vertex>.literal(v,genesis)); round[node].set(1)
                } else: {
                    With(rounds.filter { r in r > round[node] }) { r in
                        With(Subsets(of: vs.filter { v in FormalCall(as: Int.self, "Round", v) == r-1 })) { delivered in
                            let ids = delivered.mapping { v in v[1].assuming(Member.self) }
                            let prev = FormalCall(as: Vertex.self, "LeaderVertex", r-1)
                            let earlier = FormalCall(as: Vertex.self, "LeaderVertex", r-2)
                            let v = Pair<Member, Int>.literal(node, r).assuming(Vertex.self)
                            When(FormalCall(as: Bool.self, "Quorum", ids) && (r < gst || correct.isSubset(of: ids)))
                            When(!delivered.contains(prev) || FormalCall(as: Set<Vertex>.self, "Children", prev).contains(earlier)
                                || FormalCall(as: Bool.self, "Quorum", delivered.filter { x in
                                    !FormalCall(as: Set<Vertex>.self, "Children", x).contains(earlier)
                                }.mapping { x in x[1].assuming(Member.self) }))
                            When(v != FormalCall(as: Vertex.self, "LeaderVertex", r) || delivered.contains(prev)
                                || FormalCall(as: Bool.self, "Quorum", vs.filter { x in
                                    FormalCall(as: Int.self, "Round", x) == r && !FormalCall(as: Set<Vertex>.self, "Children", x).contains(prev)
                                }.mapping { x in x[1].assuming(Member.self) }.inserting(node)))
                            If(r > 2 && FormalCall(as: Bool.self, "Quorum", delivered.filter { x in
                                FormalCall(as: Set<Vertex>.self, "Children", x).contains(earlier)
                            }.mapping { x in x[1].assuming(Member.self) })) {
                                log[node].set(FormalCall(as: [Vertex].self, "Linearize", earlier))
                            }
                            round[node].set(r); vs.insert(v)
                            es.set(es.union(delivered.mapping { x in Pair<Vertex,Vertex>.literal(v,x) }))
                        }
                    }
                }
            }
            Do(Step.byzantineNode, over: Set<Member>([.n1])) { node in
                With(rounds) { r in
                    let v = Pair<Member, Int>.literal(node, r).assuming(Vertex.self)
                    When(!vs.contains(v))
                    If(r == 1) {
                        vs.insert(v); es.insert(Pair<Vertex,Vertex>.literal(v,genesis))
                    } else: {
                        With(Subsets(of: vs.filter { x in FormalCall(as: Int.self,"Round",x) == r-1 })) { delivered in
                            When(FormalCall(as: Bool.self,"Quorum",delivered.mapping { x in x[1].assuming(Member.self) }))
                            vs.insert(v); es.set(es.union(delivered.mapping { x in Pair<Vertex,Vertex>.literal(v,x) }))
                        }
                    }
                }
            }
            Do(Step.terminate, when: correct.allSatisfy { n in round[n] == 5 }) { Skip() }
            Constraint(correct.allSatisfy { n in round[n] >= 0 && round[n] <= 5 })
            Invariant("TypeOK") {
                vs.removing(genesis).allSatisfy { v in nodes.contains(v[1].assuming(Member.self)) && FormalCall(as: Int.self,"Round",v) > 0
                    && FormalCall(as: Set<Vertex>.self,"Children",v).allSatisfy { c in FormalCall(as: Int.self,"Round",c) == FormalCall(as: Int.self,"Round",v)-1 } }
                es.allSatisfy { e in vs.contains(e.first()) && vs.contains(e.second()) }
                correct.allSatisfy { n in round[n] >= 0 }
            }
            Invariant("Agreement") {
                correct.allSatisfy { a in correct.allSatisfy { b in
                    IntRange(1, through: log[a].count).allSatisfy { i in i > log[b].count || log[a][i] == log[b][i] }
                } }
            }
            Invariant("Liveness") {
                rounds.allSatisfy { r in r < gst || schedule[(r-1) % schedule.count + 1] == Member.n1 || correct.allSatisfy { n in
                    round[n] < r+2 || IntRange(1, through: log[n].count).contains { i in log[n][i] == FormalCall(as: Vertex.self,"LeaderVertex",r) }
                } }
            }
            Validation("ThreeNodes") { Bind(schedule, to: [Member.n1, Member.n2, Member.n3]) }
            Validation("FourNodes") { Bind(schedule, to: [Member.n1, Member.n2, Member.n3, Member.n4]) }
        }
    }
}
