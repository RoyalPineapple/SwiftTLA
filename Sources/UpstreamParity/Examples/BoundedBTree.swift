// The request, search and split phases expose the same twelve state fields as the published B-tree.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/btree/MCbtree.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BoundedBTree: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case absent = "nil", missing, x, y, z, ready
        case get = "get_value", find = "find_leaf_to_add", which = "which_to_split", add = "add_to_leaf"
        case splitLeaf = "split_leaf", splitInner = "split_inner", rootLeaf = "split_root_leaf"
        case rootInner = "split_root_inner", update = "update_leaf"
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
        package static var defaultValue: Self { .absent }
    }
    package typealias Index = Pair<Int,Int>
    package typealias Node = OneOf<Int,Atom>
    package typealias Entry = OneOf<Int,Atom>
    package typealias Arguments = [Entry]
    package typealias Argument = OneOf<Arguments,Atom>
    package typealias Reply = OneOf<String,Atom>
    private enum Step: String, CaseIterable {
        case get = "GetReq", insert = "InsertReq", update = "UpdateReq", read = "GetValue", replace = "UpdateLeaf"
        case find = "FindLeafToAdd", split = "WhichToSplit", add = "AddToLeaf", leaf = "SplitLeaf"
        case rootLeaf = "SplitRootLeaf", rootInner = "SplitRootInner"
    }
    package static var spec: TLASpec {
        #spec("MCbtree") { scope in
            let maxKey = scope.parameter(tlaName:"MaxKey", as:Int.self, in:Int.all)
            let maxNode = scope.parameter(tlaName:"MaxNode", as:Int.self, in:Int.all)
            let capacity = scope.parameter(tlaName:"MaxOccupancy", as:Int.self, in:Int.all)
            let values = scope.parameter(tlaName:"Vals", as:Set<Atom>.self, in:Subsets(of:Atom.all.assuming(Set<Atom>.self)))
            let keys = IntRange(1,through:maxKey)
            let nodes = IntRange(1,through:maxNode)
            let indices = nodes.flatMapping { n in keys.mapping { k in Pair.literal(n, k).assuming(Index.self) } }
            let noNode: Node = Node.second(Atom.absent)
            let noReply: Reply = Reply.second(Atom.absent)
            let isLeaf = scope.sharedVar(initial:Dictionary<Int,Bool>.mapping(over:nodes) { _ in true })
            let keysOf = scope.sharedVar(initial:Dictionary<Int,Set<Int>>.mapping(over:nodes) { _ in Set<Int>() })
            let childOf = scope.sharedVar(initial:Dictionary<Index,Node>.mapping(over:indices) { _ in noNode })
            let lastOf = scope.sharedVar(initial:Dictionary<Int,Node>.mapping(over:nodes) { _ in noNode })
            let valOf = scope.sharedVar(initial:Dictionary<Index,Atom>.mapping(over:indices) { _ in Atom.absent })
            let free = nodes.filter { n in isLeaf[n] && keysOf[n].isEmpty }
            let root = scope.sharedVar(initial:Select(from:free) { _ in true })
            let focus: SharedVariable<Node> = scope.sharedVar(initial:noNode)
            let toSplit = scope.sharedVar(initial:[Int]())
            let op: SharedVariable<Reply> = scope.sharedVar(initial:noReply)
            let args: SharedVariable<Argument> = scope.sharedVar(initial:Argument.second(Atom.absent))
            let ret: SharedVariable<Reply> = scope.sharedVar(initial:noReply)
            let state = scope.sharedVar(initial:Atom.ready)
            FormalDefinition("ClosestLarger", taking: Set<Int>.self, Int.self) { keys, key -> Expr<Int> in
                Select(from: keys) { i in i > key && keys.allSatisfy { j in j <= key || i <= j } }
            }
            FormalDefinition("ChildNodeFor", taking: Int.self, Int.self) { n, key -> Expr<Int> in
                If(keysOf[n].contains { j in j > key },
                   then: childOf[Pair<Int, Int>.literal(n, FormalCall(as: Int.self, "ClosestLarger", keysOf[n], key))],
                   else: lastOf[n]).assuming(Int.self)
            }
            FormalDefinition("FindLeafNode", taking:Int.self) { key -> Expr<Int> in
                LetRec("Walk",over:nodes,taking:Int.self,{ walk,n in
                    If(isLeaf[n],then:n,else:walk(FormalCall(as:Int.self,"ChildNodeFor",n,key)))
                },in:{ walk in walk(root) })
            }
            FormalDefinition("ParentOf",taking:Int.self) { n -> Expr<Int> in
                Select(from:nodes) { p in lastOf[p] == Node.first(n) || keys.contains { k in childOf[Pair.literal(p,k)] == Node.first(n) } }
            }
            let get = Do(Step.get,over:keys) { k in
                When(state == Atom.ready)
                op.set(Reply.first("get")); args.set(Argument.first([Entry]().appending(Entry.first(k))))
                ret.set(noReply); state.set(Atom.get)
            }
            WeakFairness(get,on:op)
            Do(Step.insert, over: keys, values) { k, v in
                When(state == Atom.ready)
                op.set(Reply.first("insert")); args.set(Argument.first(Pair<Int, Atom>.literal(k, v).assuming(Arguments.self)))
                ret.set(noReply); state.set(Atom.find)
            }
            Do(Step.update, over: keys, values) { k, v in
                When(state == Atom.ready)
                op.set(Reply.first("update")); args.set(Argument.first(Pair<Int, Atom>.literal(k, v).assuming(Arguments.self)))
                ret.set(noReply); focus.set(Node.first(FormalCall(as:Int.self,"FindLeafNode",k))); state.set(Atom.update)
            }
            Do(Step.read,when:state == Atom.get) {
                let k = args.assuming(Arguments.self)[1].assuming(Int.self)
                let leaf = FormalCall(as:Int.self,"FindLeafNode",k)
                ret.set(Reply.second(If(keysOf[leaf].contains(k),then:valOf[Pair.literal(leaf,k)],else:Atom.missing)))
                state.set(Atom.ready)
            }
            Do(Step.replace,when:state == Atom.update) {
                let k = args.assuming(Arguments.self)[1].assuming(Int.self)
                let n = focus.assuming(Int.self)
                If(keysOf[n].contains(k)) {
                    valOf[Pair.literal(n,k)].set(args.assuming(Arguments.self)[2].assuming(Atom.self)); ret.set(Reply.first("ok"))
                } else: { ret.set(Reply.first("error")) }
                focus.set(noNode); state.set(Atom.ready)
            }
            Do(Step.find,when:state == Atom.find) {
                let n = FormalCall(as:Int.self,"FindLeafNode",args.assuming(Arguments.self)[1].assuming(Int.self))
                focus.set(Node.first(n))
                toSplit.set(If(keysOf[n].count == capacity,then:[Int]().appending(n),else:[Int]()))
                state.set(If(keysOf[n].count == capacity,then:Atom.which,else:Atom.add))
            }
            Do(Step.split,when:state == Atom.which) {
                Let(toSplit.head()) { n in
                    If(n == root) { state.set(If(isLeaf[n],then:Atom.rootLeaf,else:Atom.rootInner)) }
                    else: {
                        let parent = FormalCall(as:Int.self,"ParentOf",n)
                        If(keysOf[parent].count == capacity) { toSplit.set(toSplit.prepending(parent)) }
                        else: { state.set(If(isLeaf[n],then:Atom.splitLeaf,else:Atom.splitInner)) }
                    }
                }
            }
            Do(Step.add,when:state == Atom.add) {
                let k = args.assuming(Arguments.self)[1].assuming(Int.self)
                let n = focus.assuming(Int.self)
                If(!keysOf[n].contains(k)) {
                    valOf[Pair.literal(n,k)].set(args.assuming(Arguments.self)[2].assuming(Atom.self))
                    keysOf[n].insert(k); ret.set(Reply.first("ok"))
                } else: { ret.set(Reply.first("error")) }
                state.set(Atom.ready)
            }
            FormalDefinition("PivotOf",taking:Set<Int>.self) { ks -> Expr<Int> in
                Select(from:ks) { k in
                    ks.filter { x in x < k }.count == ks.count.integerDivided(by: 2)
                }
            }
            // Pin source values before mutating the tree. SplitRootInner keeps focus and valOf.
            Do(Step.leaf,when:state == Atom.splitLeaf) {
                Let(toSplit.head()) { left in
                    Let(Select(from:free) { _ in true }) { right in
                        Let(FormalCall(as:Int.self,"ParentOf",left)) { parent in
                            Let(keysOf[left]) { oldKeys in
                                Let(FormalCall(as:Int.self,"PivotOf",oldKeys)) { pivot in
                                    Let(childOf) { oldChildren in
                                        Let(valOf) { oldValues in
                                            Let(lastOf[parent] == Node.first(left)) { wasLast in
                                                Let(If(wasLast,then:pivot,else:Select(from:keysOf[parent]) { k in oldChildren[Pair.literal(parent,k)] == Node.first(left) })) { parentKey in
                                                    If(wasLast) { lastOf[parent].set(Node.first(right)) }
                                                    else: { childOf[Pair.literal(parent,parentKey)].set(Node.first(right)) }
                                                    isLeaf[right].set(true)
                                                    keysOf[parent].insert(pivot)
                                                    keysOf[left].set(oldKeys.filter { k in k < pivot })
                                                    keysOf[right].set(oldKeys.filter { k in k >= pivot })
                                                    childOf[Pair.literal(parent,pivot)].set(Node.first(left))
                                                    valOf.set(Dictionary<Index,Atom>.mapping(over:indices) { i in
                                                        let n = i.first()
                                                        let k = i.second()
                                                        return If(oldKeys.contains(k) && k >= pivot && n == left,then:Atom.absent,else:
                                                            If(oldKeys.contains(k) && k >= pivot && n == right,then:oldValues[Pair.literal(left,k)],else:oldValues[i]))
                                                    })
                                                    focus.set(Node.first(If(args.assuming(Arguments.self)[1].assuming(Int.self) < pivot,then:left,else:right)))
                                                    state.set(Atom.add)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Do(Step.rootLeaf,when:state == Atom.rootLeaf) {
                Let(toSplit.head()) { left in
                    Let(Select(from:free) { _ in true }) { right in
                        Let(Select(from:free.removing(right)) { _ in true }) { parent in
                            Let(keysOf[left]) { oldKeys in
                                Let(FormalCall(as:Int.self,"PivotOf",oldKeys)) { pivot in
                                    Let(childOf) { oldChildren in
                                        Let(valOf) { oldValues in
                                            root.set(parent)
                                            isLeaf[parent].set(false)
                                            lastOf[parent].set(Node.first(right))
                                            isLeaf[right].set(true)
                                            keysOf[parent].insert(pivot)
                                            keysOf[left].set(oldKeys.filter { k in k < pivot })
                                            keysOf[right].set(oldKeys.filter { k in k >= pivot })
                                            childOf[Pair.literal(parent,pivot)].set(Node.first(left))
                                            valOf.set(Dictionary<Index,Atom>.mapping(over:indices) { i in
                                                let n = i.first()
                                                let k = i.second()
                                                return If(oldKeys.contains(k) && k >= pivot && n == left,then:Atom.absent,else:
                                                    If(oldKeys.contains(k) && k >= pivot && n == right,then:oldValues[Pair.literal(left,k)],else:oldValues[i]))
                                            })
                                            focus.set(Node.first(If(args.assuming(Arguments.self)[1].assuming(Int.self) < pivot,then:left,else:right)))
                                            state.set(Atom.add)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Do(Step.rootInner,when:state == Atom.rootInner) {
                Let(toSplit.head()) { left in
                    Let(Select(from:free) { _ in true }) { right in
                        Let(Select(from:free.removing(right)) { _ in true }) { parent in
                            Let(keysOf[left]) { oldKeys in
                                Let(FormalCall(as:Int.self,"PivotOf",oldKeys)) { pivot in
                                    Let(childOf) { oldChildren in
                                        Let(lastOf[left]) { oldLast in
                                            root.set(parent)
                                            isLeaf[parent].set(false)
                                            lastOf[parent].set(Node.first(right))
                                            isLeaf[right].set(false)
                                            keysOf[parent].insert(pivot)
                                            keysOf[left].set(oldKeys.filter { k in k < pivot })
                                            keysOf[right].set(oldKeys.filter { k in k > pivot })
                                            childOf.set(Dictionary<Index,Node>.mapping(over:indices) { i in
                                                let n = i.first()
                                                let k = i.second()
                                                return If(n == parent && k == pivot,then:Node.first(left),else:
                                                    If(oldKeys.contains(k) && k > pivot && n == left,then:noNode,else:
                                                        If(oldKeys.contains(k) && k > pivot && n == right,then:oldChildren[Pair.literal(left,k)],else:oldChildren[i])))
                                            })
                                            lastOf[left].set(oldChildren[Pair.literal(left,pivot)]); lastOf[right].set(oldLast)
                                            toSplit.set([Int]())
                                            state.set(Atom.add)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            let leaves = nodes.filter { n in isLeaf[n] }
            let inners = nodes.subtracting(leaves)
            let nodeValues = nodes.mapping { n in Node.first(n) }.inserting(noNode)
            Invariant("TypeOk") {
                nodes.contains(root) && nodeValues.contains(focus) && isLeaf.keys == nodes && keysOf.keys == nodes
                childOf.keys == indices && lastOf.keys == nodes && valOf.keys == indices
                nodes.allSatisfy { n in keysOf[n].isSubset(of:keys) && nodeValues.contains(lastOf[n]) }
                indices.allSatisfy { i in nodeValues.contains(childOf[i]) && values.inserting(Atom.absent).contains(valOf[i]) }
                IntRange(1,through:toSplit.count).allSatisfy { i in nodes.contains(toSplit[i]) }
                op == noReply || op == Reply.first("get") || op == Reply.first("insert") || op == Reply.first("update")
                ret == noReply || ret == Reply.second(Atom.missing) || ret == Reply.first("ok") || ret == Reply.first("error") || values.contains { v in ret == Reply.second(v) }
                Set<Atom>([.ready,.get,.find,.which,.add,.splitLeaf,.splitInner,.rootLeaf,.rootInner,.update]).contains(state)
            }
            Invariant("InnersMustHaveLast") { inners.allSatisfy { n in lastOf[n] != noNode } }
            Invariant("LeavesCantHaveLast") { leaves.allSatisfy { n in lastOf[n] == noNode } }
            Invariant("KeyOrderPreserved") { inners.allSatisfy { n in keysOf[n].allSatisfy { k in
                keysOf[childOf[Pair.literal(n,k)].assuming(Int.self)].allSatisfy { j in j < k }
            } } }
            Invariant("KeysInLeavesAreUnique") {
                leaves.allSatisfy { a in leaves.allSatisfy { b in a == b || keysOf[a].intersection(keysOf[b]).isEmpty } }
            }
            Invariant("FreeNodesRemain") { !free.isEmpty }
            Validation("Upstream") {
                Bind(maxKey,to:4); Bind(maxNode,to:8); Bind(capacity,to:2); Bind(values,to:Set<Atom>([.x,.y,.z]))
            }
        }
    }
}
